defmodule SupervisedSlicesWeb.BillingLive.Setup do
  use SupervisedSlicesWeb, :live_view

  on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_required}

  alias SupervisedSlices.Billing

  def render(assigns) do
    ~H"""
    <div class="grid min-h-dvh place-items-center bg-surface p-4 sm:p-6 lg:p-8">
      <div class="mx-auto w-full max-w-md">
        <div class="auth-card rounded-3xl p-8 sm:p-10">
          <%!-- Logo / Banner --%>
          <div class="flex flex-col items-center mb-8">
            <img
              src="/images/logo.svg"
              alt="Supervised Slices"
              class="size-20 rounded-2xl shadow-lg -rotate-3 mb-6"
            />
            <h1 class="font-headline font-black text-3xl tracking-tighter uppercase italic text-on-surface text-center">
              Activate Your Kitchen
            </h1>
            <p class="text-on-surface-variant/60 text-sm mt-2 text-center font-medium">
              One subscription. Every order, managed.
            </p>
          </div>

          <%!-- Org details --%>
          <div class="bg-surface-container-low rounded-2xl px-6 py-4 mb-8">
            <p class="font-headline text-[10px] font-black uppercase tracking-[0.2em] text-on-surface-variant/40 mb-1">
              Kitchen
            </p>
            <p class="font-headline font-black text-xl text-on-surface tracking-tight">
              {@org.name}
            </p>
          </div>

          <%!-- What's included --%>
          <ul class="space-y-3 mb-8 text-sm text-on-surface/70">
            <li class="flex items-center gap-3">
              <span class="size-5 rounded-full bg-primary/10 text-primary flex items-center justify-center text-xs font-black">
                ✓
              </span>
              Real-time order management
            </li>
            <li class="flex items-center gap-3">
              <span class="size-5 rounded-full bg-primary/10 text-primary flex items-center justify-center text-xs font-black">
                ✓
              </span>
              Customer-facing menu &amp; ordering
            </li>
            <li class="flex items-center gap-3">
              <span class="size-5 rounded-full bg-primary/10 text-primary flex items-center justify-center text-xs font-black">
                ✓
              </span>
              Push notifications for new orders
            </li>
            <li class="flex items-center gap-3">
              <span class="size-5 rounded-full bg-primary/10 text-primary flex items-center justify-center text-xs font-black">
                ✓
              </span>
              Cancel anytime from your billing portal
            </li>
          </ul>

          <%!-- CTA --%>
          <button
            phx-click="subscribe"
            disabled={@loading}
            class="btn btn-tomato w-full h-16 rounded-2xl text-base font-black uppercase tracking-widest disabled:opacity-60"
          >
            <%= if @loading do %>
              <span class="loading loading-spinner loading-sm mr-2"></span> Redirecting to Checkout…
            <% else %>
              Subscribe &amp; Open Kitchen
            <% end %>
          </button>

          <p class="text-center text-[11px] text-on-surface-variant/40 mt-4">
            Secured by Stripe. You'll be redirected to complete payment.
          </p>
        </div>
      </div>
    </div>
    """
  end

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
         {:ok, session} <-
           Billing.create_checkout_session(org.stripe_customer_id, success_url, cancel_url) do
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
