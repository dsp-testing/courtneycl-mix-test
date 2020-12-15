defmodule HygeiaWeb.Helpers.Confirmation do
  @moduledoc false

  import HygeiaGettext

  alias Hygeia.CaseContext.Case
  alias Hygeia.CaseContext.Case.Phase
  alias Hygeia.Repo
  alias Hygeia.TenantContext
  alias HygeiaWeb.Router.Helpers, as: Routes

  @spec isolation_sms(
          conn_or_socket :: Plug.Conn.t() | Phoenix.LiveView.Socket.t(),
          case :: Case.t(),
          phase :: Phase.t()
        ) :: String.t()
  def isolation_sms(conn_or_socket, case, phase) do
    case = Repo.preload(case, :tenant)

    gettext(
      """
      You have been tested positive for the corona virus.
      Therefore you have to self isolate.
      Details: %{isolation_confirmation_link}
      """,
      isolation_confirmation_link:
        TenantContext.replace_base_url(
          case.tenant,
          Routes.pdf_url(conn_or_socket, :isolation_confirmation, case, phase),
          HygeiaWeb.Endpoint.url()
        )
    )
  end

  @spec isolation_email_subject() :: String.t()
  def isolation_email_subject, do: gettext("Isolation Order")

  @spec isolation_email_body(
          conn_or_socket :: Plug.Conn.t() | Phoenix.LiveView.Socket.t(),
          case :: Case.t(),
          phase :: Phase.t()
        ) :: String.t()
  def isolation_email_body(conn_or_socket, case, phase) do
    case = Repo.preload(case, :tenant)

    gettext(
      """
      You have been tested positive for the corona virus.
      Therefore you have to self isolate.
      Details: %{isolation_confirmation_link}
      """,
      isolation_confirmation_link:
        TenantContext.replace_base_url(
          case.tenant,
          Routes.pdf_url(conn_or_socket, :isolation_confirmation, case, phase),
          HygeiaWeb.Endpoint.url()
        )
    )
  end

  @spec quarantine_sms(
          conn_or_socket :: Plug.Conn.t() | Phoenix.LiveView.Socket.t(),
          case :: Case.t(),
          phase :: Phase.t()
        ) :: String.t()
  def quarantine_sms(conn_or_socket, case, phase) do
    case = Repo.preload(case, :tenant)

    gettext(
      """
      You have been identified as a contact person of a person with corona.
      Therefore you have to self quarantine.
      Details: %{quarantine_confirmation_link}
      """,
      quarantine_confirmation_link:
        TenantContext.replace_base_url(
          case.tenant,
          Routes.pdf_url(conn_or_socket, :quarantine_confirmation, case, phase),
          HygeiaWeb.Endpoint.url()
        )
    )
  end

  @spec quarantine_email_subject() :: String.t()
  def quarantine_email_subject, do: gettext("Quarantine Order")

  @spec quarantine_email_body(
          conn_or_socket :: Plug.Conn.t() | Phoenix.LiveView.Socket.t(),
          case :: Case.t(),
          phase :: Phase.t()
        ) :: String.t()
  def quarantine_email_body(conn_or_socket, case, phase) do
    case = Repo.preload(case, :tenant)

    gettext(
      """
      You have been identified as a contact person of a person with corona.
      Therefore you have to self quarantine.
      Details: %{quarantine_confirmation_link}
      """,
      quarantine_confirmation_link:
        TenantContext.replace_base_url(
          case.tenant,
          Routes.pdf_url(conn_or_socket, :quarantine_confirmation, case, phase),
          HygeiaWeb.Endpoint.url()
        )
    )
  end
end
