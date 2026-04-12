defmodule SupervisedSlicesWeb.BillingLive.Success do
  use SupervisedSlicesWeb, :live_view

  on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_required}

  def render(assigns) do
    ~H"""
    <div class="grid min-h-dvh place-items-center bg-surface p-4 sm:p-6 lg:p-8">
      <div class="mx-auto w-full max-w-md text-center">
        <div class="auth-card rounded-3xl p-8 sm:p-10">
          <div class="size-20 rounded-full bg-primary/10 flex items-center justify-center mx-auto mb-6">
            <span class="text-4xl">🎉</span>
          </div>

          <h1 class="font-headline font-black text-3xl tracking-tighter uppercase italic text-on-surface mb-3">
            You're Subscribed!
          </h1>

          <p class="text-on-surface/60 text-sm mb-2">
            <strong class="text-on-surface font-semibold">{@org.name}</strong> is now active.
          </p>
          <p class="text-on-surface-variant/50 text-xs mb-8">
            Your subscription is being confirmed — this usually takes just a moment.
          </p>

          <.link
            navigate={~p"/kitchen/#{@org.slug}"}
            class="btn btn-tomato w-full h-16 rounded-2xl text-base font-black uppercase tracking-widest inline-flex items-center justify-center"
          >
            Enter the Kitchen
          </.link>

          <p class="text-[11px] text-on-surface-variant/40 mt-4">
            Manage billing anytime from Kitchen → Settings → Billing.
          </p>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    org = socket.assigns.org

    if is_nil(org) do
      {:ok, redirect(socket, to: ~p"/")}
    else
      {:ok, assign(socket, :org, org)}
    end
  end
end
