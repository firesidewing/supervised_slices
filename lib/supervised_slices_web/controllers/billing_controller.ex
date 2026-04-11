defmodule SupervisedSlicesWeb.BillingController do
  use SupervisedSlicesWeb, :controller

  alias SupervisedSlices.Billing

  @doc """
  Redirects the current user to their Stripe Customer Portal where they can
  manage their subscription, update payment methods, and view invoices.

  Accessible from the kitchen settings page at /kitchen/:org_slug/settings.
  """
  def portal(conn, %{"org_slug" => slug}) do
    org =
      SupervisedSlices.Orgs.Organization
      |> Ash.Query.for_read(:by_slug, %{slug: slug})
      |> Ash.read_one!(authorize?: false)

    if is_nil(org) or is_nil(org.stripe_customer_id) do
      conn
      |> put_flash(:error, "Billing not yet set up for this kitchen.")
      |> redirect(to: ~p"/billing/setup/#{slug}")
    else
      return_url = SupervisedSlicesWeb.Endpoint.url() <> ~p"/kitchen/#{slug}/settings"

      case Billing.create_portal_session(org.stripe_customer_id, return_url) do
        {:ok, session} ->
          redirect(conn, external: session.url)

        {:error, reason} ->
          conn
          |> put_flash(:error, "Could not open billing portal: #{inspect(reason)}")
          |> redirect(to: ~p"/kitchen/#{slug}/settings")
      end
    end
  end
end
