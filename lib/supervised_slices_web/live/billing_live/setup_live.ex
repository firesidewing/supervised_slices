defmodule SupervisedSlicesWeb.BillingLive.Setup do
  use SupervisedSlicesWeb, :live_view

  on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_required}

  alias SupervisedSlices.Billing

  def mount(_params, _session, socket) do
    org = socket.assigns.org
    user = socket.assigns.current_user

    if is_nil(org) do
      {:ok, redirect(socket, to: ~p"/")}
    else
      if org.subscription_status in [:active, :trialing] do
        {:ok, redirect(socket, to: ~p"/kitchen/#{org.slug}")}
      else
        {:ok,
         socket
         |> assign(:org, org)
         |> assign(:user, user)
         |> assign(:loading, false)}
      end
    end
  end

  def handle_event("subscribe", _params, socket) do
    socket = assign(socket, :loading, true)
    org = socket.assigns.org
    user = socket.assigns.user

    base_url = SupervisedSlicesWeb.Endpoint.url()
    success_url = base_url <> ~p"/billing/success/#{org.slug}"
    cancel_url = base_url <> ~p"/billing/setup/#{org.slug}"

    with {:ok, org} <- Billing.create_customer_for_org(org, user.email),
         {:ok, session} <- Billing.create_checkout_session(org.stripe_customer_id, success_url, cancel_url) do
      {:noreply, redirect(socket, external: session.url)}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> put_flash(:error, "Could not start checkout: #{inspect(reason)}")}
    end
  end
end
