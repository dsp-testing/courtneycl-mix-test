defmodule Hygeia.OrganisationContext do
  @moduledoc """
  The OrganisationContext context.
  """

  use Hygeia, :context

  alias Hygeia.CaseContext.Address
  alias Hygeia.CaseContext.Person
  alias Hygeia.OrganisationContext.Affiliation
  alias Hygeia.OrganisationContext.Organisation
  alias Hygeia.OrganisationContext.Position

  @doc """
  Returns the list of organisations.

  ## Examples

      iex> list_organisations()
      [%Organisation{}, ...]

  """
  @spec list_organisations :: [Organisation.t()]
  def list_organisations, do: Repo.all(list_organisations_query())

  @spec list_organisations_query :: Ecto.Queryable.t()
  def list_organisations_query,
    do: from(organisation in Organisation, order_by: organisation.name)

  @spec list_organisations_by_ids(ids :: [String.t()]) :: [Organisation.t()]
  def list_organisations_by_ids(ids)
  def list_organisations_by_ids([]), do: []

  def list_organisations_by_ids(ids),
    do:
      Repo.all(from(organisation in list_organisations_query(), where: organisation.uuid in ^ids))

  @spec list_possible_organisation_duplicates(organisation :: Organisation.t()) ::
          Ecto.Queryable.t()
  def list_possible_organisation_duplicates(
        %Organisation{name: name, address: address, uuid: uuid} = _organisation
      ),
      do:
        list_organisations_query()
        |> filter_similar_organisation_names(name)
        |> filter_same_organisation_address(address)
        |> remove_uuid(uuid)
        |> Repo.all()

  defp filter_similar_organisation_names(query, name),
    do: from(organisation in query, where: fragment("? % ?", ^name, organisation.name))

  defp filter_same_organisation_address(query, nil), do: query

  defp filter_same_organisation_address(query, %Address{address: nil}), do: query
  defp filter_same_organisation_address(query, %Address{address: ""}), do: query

  defp filter_same_organisation_address(query, %Address{
         address: address,
         zip: zip,
         place: place,
         country: country
       }),
       do:
         from(organisation in query,
           or_where:
             fragment(
               "? <@ ?",
               ^%{address: address, zip: zip, place: place, country: country},
               organisation.address
             )
         )

  defp remove_uuid(query, nil), do: query

  defp remove_uuid(query, uuid),
    do: from(organisation in query, where: organisation.uuid != ^uuid)

  @spec fulltext_organisation_search_query(query :: String.t(), limit :: pos_integer()) ::
          Ecto.Query.t()
  def fulltext_organisation_search_query(query, limit \\ 10),
    do:
      from(organisation in Organisation,
        where: fragment("?.fulltext @@ WEBSEARCH_TO_TSQUERY('german', ?)", organisation, ^query),
        order_by: [
          desc:
            fragment(
              "TS_RANK_CD(?.fulltext, WEBSEARCH_TO_TSQUERY('german', ?))",
              organisation,
              ^query
            )
        ],
        limit: ^limit
      )

  @spec fulltext_organisation_search(query :: String.t(), limit :: pos_integer()) :: [
          Organisation.t()
        ]
  def fulltext_organisation_search(query, limit \\ 10),
    do: Repo.all(fulltext_organisation_search_query(query, limit))

  @doc """
  Gets a single organisation.

  Raises `Ecto.NoResultsError` if the Organisation does not exist.

  ## Examples

      iex> get_organisation!(123)
      %Organisation{}

      iex> get_organisation!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_organisation!(id :: String.t()) :: Organisation.t()
  def get_organisation!(id), do: Repo.get!(Organisation, id)

  @doc """
  Creates a organisation.

  ## Examples

      iex> create_organisation(%{field: value})
      {:ok, %Organisation{}}

      iex> create_organisation(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_organisation(attrs :: Hygeia.ecto_changeset_params()) ::
          {:ok, Organisation.t()} | {:error, Ecto.Changeset.t(Organisation.t())}
  def create_organisation(attrs \\ %{}),
    do:
      %Organisation{}
      |> change_organisation(attrs)
      |> versioning_insert()
      |> broadcast("organisations", :create)
      |> versioning_extract()

  @doc """
  Updates a organisation.

  ## Examples

      iex> update_organisation(organisation, %{field: new_value})
      {:ok, %Organisation{}}

      iex> update_organisation(organisation, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_organisation(
          organisation :: Organisation.t(),
          attrs :: Hygeia.ecto_changeset_params()
        ) ::
          {:ok, Organisation.t()} | {:error, Ecto.Changeset.t(Organisation.t())}
  def update_organisation(%Organisation{} = organisation, attrs),
    do:
      organisation
      |> change_organisation(attrs)
      |> versioning_update()
      |> broadcast("organisations", :update)
      |> versioning_extract()

  @spec merge_organisations(delete :: Organisation.t(), into :: Organisation.t()) ::
          {:ok, Organisation.t()}
  def merge_organisations(
        %Organisation{uuid: delete_uuid} = delete,
        %Organisation{uuid: into_uuid} = into
      ) do
    delete = Repo.preload(delete, :related_cases)
    into = Repo.preload(into, :related_cases)

    Repo.transaction(fn ->
      affiliation_updates =
        delete
        |> Ecto.assoc(:affiliations)
        |> Repo.stream()
        |> Enum.reduce(Ecto.Multi.new(), fn %Affiliation{uuid: uuid} = affiliation, acc ->
          PaperTrail.Multi.update(
            acc,
            uuid,
            Ecto.Changeset.change(affiliation, %{organisation_uuid: into_uuid})
          )
        end)

      position_updates =
        delete
        |> Ecto.assoc(:positions)
        |> Repo.stream()
        |> Enum.reduce(Ecto.Multi.new(), fn %Position{uuid: uuid} = position, acc ->
          PaperTrail.Multi.update(
            acc,
            uuid,
            Ecto.Changeset.change(position, %{organisation_uuid: into_uuid})
          )
        end)

      {:ok, _updates} =
        affiliation_updates
        |> Ecto.Multi.append(position_updates)
        |> Ecto.Multi.update(
          {:add_related_cases, into_uuid},
          into
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.put_assoc(:related_cases, into.related_cases ++ delete.related_cases)
        )
        |> Ecto.Multi.update(
          {:remove_related_cases, delete_uuid},
          delete
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.put_assoc(:related_cases, [])
        )
        |> PaperTrail.Multi.delete({:delete, delete_uuid}, Ecto.Changeset.change(delete))
        |> Repo.transaction()

      get_organisation!(into_uuid)
    end)
  end

  @doc """
  Deletes a organisation.

  ## Examples

      iex> delete_organisation(organisation)
      {:ok, %Organisation{}}

      iex> delete_organisation(organisation)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_organisation(organisation :: Organisation.t()) ::
          {:ok, Organisation.t()} | {:error, Ecto.Changeset.t(Organisation.t())}
  def delete_organisation(%Organisation{} = organisation) do
    positions = Repo.preload(organisation, :positions).positions

    Repo.transaction(fn ->
      positions
      |> Enum.map(&delete_position/1)
      |> Enum.each(fn
        {:ok, _position} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end)

      organisation
      |> change_organisation()
      |> versioning_delete()
      |> broadcast("organisations", :delete)
      |> versioning_extract()
      |> case do
        {:ok, organisation} -> organisation
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking organisation changes.

  ## Examples

      iex> change_organisation(organisation)
      %Ecto.Changeset{data: %Organisation{}}

  """
  @spec change_organisation(
          organisation :: Organisation.t() | Organisation.empty(),
          attrs :: Hygeia.ecto_changeset_params()
        ) ::
          Ecto.Changeset.t(Organisation.t())
  def change_organisation(%Organisation{} = organisation, attrs \\ %{}) do
    Organisation.changeset(organisation, attrs)
  end

  @doc """
  Returns the list of positions.

  ## Examples

      iex> list_positions()
      [%Position{}, ...]

  """
  @spec list_positions :: [Position.t()]
  def list_positions, do: Repo.all(Position)

  @doc """
  Gets a single position.

  Raises `Ecto.NoResultsError` if the Position does not exist.

  ## Examples

      iex> get_position!(123)
      %Position{}

      iex> get_position!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_position!(id :: String.t()) :: Position.t()
  def get_position!(id), do: Repo.get!(Position, id)

  @doc """
  Creates a position.

  ## Examples

      iex> create_position(%{field: value})
      {:ok, %Position{}}

      iex> create_position(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_position(attrs :: Hygeia.ecto_changeset_params()) ::
          {:ok, Position.t()} | {:error, Ecto.Changeset.t(Position.t())}
  def create_position(attrs \\ %{}) do
    %Position{}
    |> change_position(attrs)
    |> versioning_insert()
    |> broadcast("positions", :create)
    |> versioning_extract()
  end

  @doc """
  Updates a position.

  ## Examples

      iex> update_position(position, %{field: new_value})
      {:ok, %Position{}}

      iex> update_position(position, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_position(
          position :: Position.t(),
          attrs :: Hygeia.ecto_changeset_params()
        ) ::
          {:ok, Position.t()} | {:error, Ecto.Changeset.t(Position.t())}
  def update_position(%Position{} = position, attrs) do
    position
    |> change_position(attrs)
    |> versioning_update()
    |> broadcast("positions", :update)
    |> versioning_extract()
  end

  @doc """
  Deletes a position.

  ## Examples

      iex> delete_position(position)
      {:ok, %Position{}}

      iex> delete_position(position)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_position(position :: Position.t()) ::
          {:ok, Position.t()} | {:error, Ecto.Changeset.t(Position.t())}
  def delete_position(%Position{} = position) do
    position
    |> change_position()
    |> versioning_delete()
    |> broadcast("positions", :delete)
    |> versioning_extract()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking position changes.

  ## Examples

      iex> change_position(position)
      %Ecto.Changeset{data: %Position{}}

  """
  @spec change_position(
          position :: Position.t() | Position.empty(),
          attrs :: Hygeia.ecto_changeset_params()
        ) ::
          Ecto.Changeset.t(Position.t())
  def change_position(%Position{} = position, attrs \\ %{}) do
    Position.changeset(position, attrs)
  end

  @doc """
  Returns the list of affiliations.

  ## Examples

      iex> list_affiliations()
      [%Affiliation{}, ...]

  """
  @spec list_affiliations :: [Affiliation.t()]
  def list_affiliations, do: Repo.all(Affiliation)

  @doc """
  Gets a single affiliation.

  Raises `Ecto.NoResultsError` if the Affiliation does not exist.

  ## Examples

      iex> get_affiliation!(123)
      %Affiliation{}

      iex> get_affiliation!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_affiliation!(id :: String.t()) :: Affiliation.t()
  def get_affiliation!(id), do: Repo.get!(Affiliation, id)

  @doc """
  Creates a affiliation.

  ## Examples

      iex> create_affiliation(%{field: value})
      {:ok, %Affiliation{}}

      iex> create_affiliation(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_affiliation(
          person :: Person.t(),
          organisation :: Organisation.t(),
          attrs :: Hygeia.ecto_changeset_params()
        ) :: {:ok, Affiliation.t()} | {:error, Ecto.Changeset.t(Affiliation.t())}
  def create_affiliation(
        %Person{} = person,
        %Organisation{uuid: organisation_uuid} = _organisation,
        attrs \\ %{}
      ),
      do:
        person
        |> Ecto.build_assoc(:affiliations, %{organisation_uuid: organisation_uuid})
        |> change_affiliation(attrs)
        |> versioning_insert()
        |> broadcast(
          "affiliations",
          :create,
          & &1.uuid,
          &["people:#{&1.person_uuid}", "organisations:#{&1.organisation_uuid}"]
        )
        |> versioning_extract()

  @doc """
  Updates a affiliation.

  ## Examples

      iex> update_affiliation(affiliation, %{field: new_value})
      {:ok, %Affiliation{}}

      iex> update_affiliation(affiliation, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_affiliation(
          affiliation :: Affiliation.t(),
          attrs :: Hygeia.ecto_changeset_params()
        ) :: {:ok, Affiliation.t()} | {:error, Ecto.Changeset.t(Affiliation.t())}
  def update_affiliation(%Affiliation{} = affiliation, attrs),
    do:
      affiliation
      |> change_affiliation(attrs)
      |> versioning_update()
      |> broadcast(
        "affiliations",
        :update,
        & &1.uuid,
        &["people:#{&1.person_uuid}", "organisations:#{&1.organisation_uuid}"]
      )
      |> versioning_extract()

  @doc """
  Deletes a affiliation.

  ## Examples

      iex> delete_affiliation(affiliation)
      {:ok, %Affiliation{}}

      iex> delete_affiliation(affiliation)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_affiliation(affiliation :: Affiliation.t()) ::
          {:ok, Affiliation.t()} | {:error, Ecto.Changeset.t(Affiliation.t())}
  def delete_affiliation(%Affiliation{} = affiliation),
    do:
      affiliation
      |> change_affiliation()
      |> versioning_delete()
      |> broadcast(
        "affiliations",
        :delete,
        & &1.uuid,
        &["people:#{&1.person_uuid}", "organisations:#{&1.organisation_uuid}"]
      )
      |> versioning_extract()

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking affiliation changes.

  ## Examples

      iex> change_affiliation(affiliation)
      %Ecto.Changeset{data: %Affiliation{}}

  """
  @spec change_affiliation(
          affiliation :: resource | Ecto.Changeset.t(resource),
          attrs :: Hygeia.ecto_changeset_params()
        ) :: Ecto.Changeset.t(resource)
        when resource: Affiliation.t() | Affiliation.empty()
  def change_affiliation(affiliation, attrs \\ %{}), do: Affiliation.changeset(affiliation, attrs)
end
