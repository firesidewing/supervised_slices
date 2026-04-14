defmodule SupervisedSlicesWeb.BillingLive.Setup do
  use SupervisedSlicesWeb, :live_view

  on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_required}

  alias SupervisedSlices.Billing

  def render(assigns) do
    ~H"""
    <div class="grid min-h-dvh place-items-center bg-surface p-4 sm:p-6 lg:p-8">
      <div class="mx-auto w-full max-w-2xl">
        <div class="auth-card rounded-3xl p-8 sm:p-10">
          <%!-- Logo / Banner --%>
          <div class="flex flex-col items-center mb-12">
            <img
              src="/images/logo.svg"
              alt="Supervised Slices"
              class="size-20 rounded-2xl shadow-lg -rotate-3 mb-6"
            />
            <h1 class="font-headline font-black text-3xl tracking-tighter uppercase italic text-on-surface text-center">
              Activate Your Kitchen
            </h1>
            <p class="text-on-surface-variant/60 text-sm mt-2 text-center font-medium">
              Choose the tier that matches your ambition.
            </p>
          </div>

          <%!-- Org details --%>
          <div class="bg-surface-container-low rounded-2xl px-6 py-4 mb-12">
            <p class="font-headline text-[10px] font-black uppercase tracking-[0.2em] text-on-surface-variant/40 mb-1">
              Organization
            </p>
            <p class="font-headline font-black text-xl text-on-surface tracking-tight">
              {@org.name}
            </p>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-8 mb-12">
            <%!-- Basic Plan --%>
            <div class="bg-surface border border-outline-variant/10 rounded-2xl p-6 flex flex-col">
              <div class="mb-4">
                <h3 class="font-headline text-xl font-black mb-1">Base Dough</h3>
                <p class="text-2xl font-headline font-black text-primary">$79<span class="text-xs text-on-surface-variant/60 font-body">/mo</span></p>
              </div>
              <ul class="space-y-3 mb-8 text-sm text-on-surface/70 flex-grow">
                <li class="flex items-center gap-2">
                  <span class="text-primary font-bold">✓</span> Online Ordering
                </li>
                <li class="flex items-center gap-2">
                  <span class="text-primary font-bold">✓</span> Menu Studio
                </li>
                <li class="flex items-center gap-2">
                  <span class="text-primary font-bold">✓</span> Kitchen Command (The Rail)
                </li>
              </ul>
              <button
                phx-click="subscribe"
                phx-value-plan="basic"
                disabled={@loading or (@org.subscription_status in [:active, :trialing] and @org.plan == :basic)}
                class="btn btn-outline btn-primary w-full h-12 rounded-xl text-xs font-black uppercase tracking-widest disabled:opacity-60"
              >
                <%= if @loading == "basic" do %>
                  <span class="loading loading-spinner loading-xs"></span>
                <% else %>
                  <%= if @org.subscription_status in [:active, :trialing] and @org.plan == :basic do %>
                    Current Plan
                  <% else %>
                    Select Base
                  <% end %>
                <% end %>
              </button>
            </div>

            <%!-- Pro Plan --%>
            <div class="bg-on-surface rounded-2xl p-6 flex flex-col text-white shadow-xl relative overflow-hidden">
              <div class="absolute top-0 right-0 bg-primary text-white px-3 py-1 font-label text-[8px] font-black tracking-widest uppercase rounded-bl-lg">
                Recommended
              </div>
              <div class="mb-4">
                <h3 class="font-headline text-xl font-black mb-1">Pro Crust</h3>
                <p class="text-2xl font-headline font-black text-primary">$149<span class="text-xs text-white/40 font-body">/mo</span></p>
              </div>
              <ul class="space-y-3 mb-8 text-sm text-white/70 flex-grow">
                <li class="flex items-center gap-2">
                  <span class="text-primary font-bold">✓</span> Everything in Base
                </li>
                <li class="flex items-center gap-2">
                  <span class="text-primary font-bold">✓</span> Order History & Analytics
                </li>
                <li class="flex items-center gap-2">
                  <span class="text-primary font-bold">✓</span> Marketing & Upselling
                </li>
              </ul>
              <button
                phx-click="subscribe"
                phx-value-plan="pro"
                disabled={@loading}
                class="btn btn-primary w-full h-12 rounded-xl text-xs font-black uppercase tracking-widest disabled:opacity-60"
              >
                <%= if @loading == "pro" do %>
                  <span class="loading loading-spinner loading-xs"></span>
                <% else %>
                  <%= if @org.subscription_status in [:active, :trialing] and @org.plan == :basic do %>
                    Upgrade to Pro
                  <% else %>
                    Select Pro
                  <% end %>
                <% end %>
              </button>
            </div>
          </div>

          <%!-- Add-on: Menu Import --%>
          <div class="bg-surface-container-high border border-outline-variant/10 rounded-2xl p-6 mb-12 flex items-center justify-between">
            <div class="flex items-center gap-4">
              <div class="p-3 bg-secondary/10 rounded-xl text-secondary">
                <span class="material-symbols-outlined">menu_book</span>
              </div>
              <div>
                <h4 class="font-headline font-black text-on-surface">Menu Import Concierge</h4>
                <p class="text-[11px] text-on-surface-variant/60 font-body">One-time setup fee per menu import.</p>
              </div>
            </div>
            <div class="text-right">
              <p class="font-headline font-black text-lg text-on-surface">$150</p>
              <%= if @org.menu_upload_purchased do %>
                <span class="text-[10px] font-black uppercase tracking-wider text-primary">
                  Purchased
                </span>
              <% else %>
                <button
                  phx-click="purchase_menu_upload"
                  disabled={@loading == "menu_upload"}
                  class="text-[10px] font-black uppercase tracking-wider text-secondary hover:underline disabled:opacity-60"
                >
                  <%= if @loading == "menu_upload" do %>
                    Processing...
                  <% else %>
                    Request Import
                  <% end %>
                </button>
              <% end %>
            </div>
          </div>

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
      if org.subscription_status in [:active, :trialing] and org.plan == :pro do
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

  def handle_event("subscribe", %{"plan" => plan}, socket) do
    socket = assign(socket, :loading, plan)
    org = socket.assigns.org
    user = socket.assigns.user

    price_id =
      case plan do
        "pro" -> Application.get_env(:supervised_slices, :stripe)[:price_id_pro]
        _ -> Application.get_env(:supervised_slices, :stripe)[:price_id_basic]
      end

    base_url = SupervisedSlicesWeb.Endpoint.url()
    success_url = base_url <> ~p"/billing/success/#{org.slug}"
    cancel_url = base_url <> ~p"/billing/setup/#{org.slug}"

    with {:ok, org} <- Billing.create_customer_for_org(org, user.email),
         {:ok, session} <-
           Billing.create_checkout_session(
             org.stripe_customer_id,
             price_id,
             plan,
             success_url,
             cancel_url
           ) do
      {:noreply, redirect(socket, external: session.url)}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> put_flash(:error, "Could not start checkout: #{inspect(reason)}")}
    end
  end

  def handle_event("purchase_menu_upload", _params, socket) do
    socket = assign(socket, :loading, "menu_upload")
    org = socket.assigns.org
    user = socket.assigns.user

    price_id = Application.get_env(:supervised_slices, :stripe)[:price_id_menu_upload]

    base_url = SupervisedSlicesWeb.Endpoint.url()
    success_url = base_url <> ~p"/billing/success/#{org.slug}"
    cancel_url = base_url <> ~p"/billing/setup/#{org.slug}"

    metadata = %{
      "menu_upload" => "true",
      "org_id" => org.id
    }

    with {:ok, org} <- Billing.create_customer_for_org(org, user.email),
         {:ok, session} <-
           Billing.create_one_time_checkout_session(
             org.stripe_customer_id,
             price_id,
             metadata,
             success_url,
             cancel_url
           ) do
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
