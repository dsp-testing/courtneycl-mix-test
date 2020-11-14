defmodule HygeiaWeb.CaseLive.Protocol do
  @moduledoc false

  use HygeiaWeb, :surface_view

  alias Hygeia.CaseContext
  alias Hygeia.CaseContext.Case
  alias Hygeia.CaseContext.ProtocolEntry
  alias Hygeia.Repo
  alias HygeiaWeb.FormError
  alias HygeiaWeb.PolimorphicInputs
  alias Surface.Components.Form
  alias Surface.Components.Form.Field
  alias Surface.Components.Form.Input.InputContext
  alias Surface.Components.Form.Label
  alias Surface.Components.Form.Select
  alias Surface.Components.Form.TextArea
  alias Surface.Components.Form.TextInput
  alias Surface.Components.Link

  @impl Phoenix.LiveView
  def handle_params(%{"id" => id} = params, uri, socket) do
    case = CaseContext.get_case!(id)

    socket =
      if authorized?(
           case,
           case socket.assigns.live_action do
             :edit -> :update
             :show -> :details
           end,
           get_auth(socket)
         ) do
        Phoenix.PubSub.subscribe(Hygeia.PubSub, "cases:#{id}")
        Phoenix.PubSub.subscribe(Hygeia.PubSub, "protocol_entries:case:#{id}")

        load_data(socket, case, params)
      else
        socket
        |> push_redirect(to: Routes.page_path(socket, :index))
        |> put_flash(:error, gettext("You are not authorized to do this action."))
      end

    super(params, uri, socket)
  end

  @impl Phoenix.LiveView
  def handle_info({_action, %ProtocolEntry{} = _protocol_entry, _version}, socket) do
    {:noreply, load_data(socket, CaseContext.get_case!(socket.assigns.case.id))}
  end

  def handle_info({:updated, %Case{} = case, _version}, socket) do
    {:noreply, load_data(socket, case)}
  end

  def handle_info({:deleted, %Case{}, _version}, socket) do
    {:noreply, redirect(socket, to: Routes.case_index_path(socket, :index))}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_event("validate", %{"protocol_entry" => protocol_entry_params}, socket) do
    {:noreply,
     socket
     |> assign(
       protocol_entry_changeset: %{
         (socket.assigns.case
          |> Ecto.build_assoc(:protocol_entries)
          |> CaseContext.change_protocol_entry(protocol_entry_params))
         | action: :validate
       }
     )
     |> maybe_block_navigation()}
  end

  def handle_event(
        "save",
        %{"protocol_entry" => %{"type" => type} = protocol_entry_params},
        socket
      )
      when not (type in ["email", "sms"]) do
    true = authorized?(ProtocolEntry, :create, get_auth(socket), %{case: socket.assigns.case})

    socket.assigns.case
    |> CaseContext.create_protocol_entry(protocol_entry_params)
    |> handle_save_response(socket)
  end

  def handle_event(
        "save",
        %{"protocol_entry" => %{"type" => "email"} = protocol_entry_params},
        socket
      ) do
    true = authorized?(ProtocolEntry, :create, get_auth(socket), %{case: socket.assigns.case})

    socket.assigns.case
    |> Ecto.build_assoc(:protocol_entries)
    |> CaseContext.change_protocol_entry(protocol_entry_params)
    |> case do
      %Ecto.Changeset{valid?: true} = changeset ->
        CaseContext.case_send_email(
          socket.assigns.case,
          Ecto.Changeset.fetch_field!(changeset, :entry).subject,
          Ecto.Changeset.fetch_field!(changeset, :entry).body
        )

      %Ecto.Changeset{valid?: false} = changeset ->
        {:error, changeset}
    end
    |> handle_save_response(socket)
  end

  def handle_event(
        "save",
        %{"protocol_entry" => %{"type" => "sms"} = protocol_entry_params},
        socket
      ) do
    true = authorized?(ProtocolEntry, :create, get_auth(socket), %{case: socket.assigns.case})

    socket.assigns.case
    |> Ecto.build_assoc(:protocol_entries)
    |> CaseContext.change_protocol_entry(protocol_entry_params)
    |> case do
      %Ecto.Changeset{valid?: true} = changeset ->
        CaseContext.case_send_sms(
          socket.assigns.case,
          Ecto.Changeset.fetch_field!(changeset, :entry).text
        )

      %Ecto.Changeset{valid?: false} = changeset ->
        {:error, changeset}
    end
    |> handle_save_response(socket)
  end

  defp handle_save_response({:ok, _protocol_entry}, socket),
    do:
      {:noreply,
       socket
       |> load_data(CaseContext.get_case!(socket.assigns.case.uuid))
       |> put_flash(:info, gettext("Protocol Entry created successfully"))}

  defp handle_save_response({:error, %Ecto.Changeset{} = changeset}, socket),
    do:
      {:noreply,
       socket
       |> assign(protocol_entry_changeset: changeset)
       |> maybe_block_navigation()}

  defp load_data(socket, case, params \\ %{}) do
    case = Repo.preload(case, protocol_entries: [], person: [])

    assign(socket,
      case: case,
      protocol_entry_changeset:
        case |> Ecto.build_assoc(:protocol_entries) |> CaseContext.change_protocol_entry(params)
    )
  end

  defp get_protocol_user(protocol_entry) do
    protocol_entry |> PaperTrail.get_version() |> Repo.preload(:user) |> Map.fetch!(:user)
  end

  defp maybe_block_navigation(
         %{assigns: %{protocol_entry_changeset: %{changes: changes}}} = socket
       ) do
    if changes == %{} do
      push_event(socket, "unblock_navigation", %{})
    else
      push_event(socket, "block_navigation", %{})
    end
  end

  defp protocol_type_type_name(Hygeia.CaseContext.Note), do: gettext("Note")
  defp protocol_type_type_name(Hygeia.CaseContext.Email), do: gettext("Email")
end
