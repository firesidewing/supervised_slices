defmodule SupervisedSlicesWeb.OrderTrackingLive do
  use SupervisedSlicesWeb, :live_view

  on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_optional}

  alias SupervisedSlices.Orders.Order
  alias SupervisedSlices.PubSubNotifier

  @status_messages %{
    pending: "Your order has been received!",
    confirmed: "Your order has been confirmed!",
    preparing: "The kitchen has started preparing your order.",
    ready: "Your order is ready!",
    completed: "Order complete. Enjoy!",
    cancelled: "This order has been cancelled."
  }

  def mount(%{"order_id" => order_id}, _session, socket) do
    %{org: org} = socket.assigns

    order =
      Order.get!(order_id,
        tenant: org.id,
        load: [:order_items, :order_updates],
        authorize?: false
      )

    if connected?(socket) do
      PubSubNotifier.subscribe_to_order(org.id, order.id)
    end

    estimated_at = DateTime.add(order.inserted_at, org.default_prep_time * 60, :second)
    vapid_public_key = Application.get_env(:supervised_slices, :vapid)[:public_key]

    {:ok,
     socket
     |> assign(:order, order)
     |> assign(:estimated_at, estimated_at)
     |> assign(:vapid_public_key, vapid_public_key)
     |> assign(:page_title, "Order ##{order_number(order)}")}
  end

  def handle_info({:order_status, order}, socket) do
    %{org: org} = socket.assigns

    loaded =
      Order.get!(order.id,
        tenant: org.id,
        load: [:order_items, :order_updates],
        authorize?: false
      )

    status_message = Map.get(@status_messages, loaded.status, "Order updated.")

    {:noreply,
     socket
     |> assign(:order, loaded)
     |> push_event("order_status_changed", %{
       status: loaded.status,
       message: status_message
     })}
  end

  def handle_info({:order_update, update}, socket) do
    order = socket.assigns.order
    existing = order.order_updates || []
    updated_order = %{order | order_updates: existing ++ [update]}

    {:noreply,
     socket
     |> assign(:order, updated_order)
     |> push_event("order_status_changed", %{
       status: order.status,
       message: "Update from the kitchen: #{update.message}"
     })}
  end

  def handle_event(
        "save_subscription",
        %{"endpoint" => endpoint, "p256dh" => p256dh, "auth" => auth},
        socket
      ) do
    %{org: org} = socket.assigns
    actor = socket.assigns[:actor]

    user_id =
      case actor do
        %SupervisedSlices.Accounts.User{id: id} -> id
        _ -> nil
      end

    session_id =
      case actor do
        %SupervisedSlices.Accounts.GuestSession{id: id} -> id
        _ -> nil
      end

    SupervisedSlices.Orders.PushSubscription
    |> Ash.Changeset.for_create(:upsert, %{
      endpoint: endpoint,
      p256dh: p256dh,
      auth: auth,
      user_id: user_id,
      session_id: session_id
    })
    |> Ash.create(tenant: org.id, authorize?: false)

    {:noreply, socket}
  end

  def render(assigns) do
    assigns = assign(assigns, :estimated_unix, DateTime.to_unix(assigns.estimated_at))

    ~H"""
    <div class="min-h-screen bg-background pb-32">
      <header class="fixed top-0 left-0 right-0 z-50 bg-background/80 backdrop-blur-md border-b border-outline-variant/10">
        <div class="max-w-5xl mx-auto px-6 h-20 flex items-center justify-between">
          <.link navigate={~p"/menu/#{@org.slug}"} class="flex items-center gap-3 group">
            <div class="w-10 h-10 rounded-xl bg-surface-container-high flex items-center justify-center group-hover:bg-primary transition-colors">
              <span class="material-symbols-outlined text-on-surface-variant group-hover:text-on-primary">
                arrow_back
              </span>
            </div>
            <h1 class="font-headline text-xl font-black tracking-tighter text-on-surface">
              {@org.name}
            </h1>
          </.link>
          <div class="flex items-center gap-4">
            <div class="hidden md:block text-right">
              <p class="font-label text-[10px] uppercase tracking-widest text-on-surface-variant font-bold">
                Status
              </p>
              <p class="font-serif text-sm font-bold text-primary italic">
                {status_label(@order.status)}
              </p>
            </div>
            <div class="w-10 h-10 rounded-full bg-surface-container-high flex items-center justify-center text-primary">
              <span class="material-symbols-outlined">person</span>
            </div>
          </div>
        </div>
      </header>

      <main class="pt-32 px-6 max-w-5xl mx-auto">
        <%!-- Header & ETA Section --%>
        <section class="mb-12 relative">
          <div class="flex flex-col md:flex-row md:items-end justify-between gap-6">
            <div>
              <span class="font-label text-[0.75rem] uppercase tracking-[0.15em] text-secondary font-bold mb-2 block">
                Order #{order_number(@order)}
              </span>
              <h2 class="font-serif text-4xl md:text-5xl font-bold tracking-tight text-on-surface leading-tight">
                {status_headline(@order.status)}
              </h2>
            </div>

            <%!-- ETA card --%>
            <div
              :if={@order.status not in [:ready, :completed, :cancelled]}
              class="bg-surface-container-lowest p-6 rounded-xl shadow-sm border border-outline-variant/10 flex flex-col items-center justify-center min-w-[180px]"
            >
              <span class="font-label text-[0.65rem] uppercase tracking-widest text-tertiary mb-1">
                Estimated Ready
              </span>
              <span
                id="order-countdown"
                phx-hook="Countdown"
                data-estimated-at={@estimated_unix}
                data-status={@order.status}
                class="font-serif text-4xl font-bold text-primary"
              >
                {format_time(@estimated_at)}
              </span>
              <span class="font-label text-[0.65rem] uppercase tracking-widest text-secondary font-bold mt-1">
                {format_date(@estimated_at)}
              </span>
            </div>

            <%!-- Ready for Pickup card --%>
            <div
              :if={@order.status == :ready}
              class="bg-secondary-container p-6 rounded-xl shadow-md border border-secondary flex flex-col items-center justify-center min-w-[180px] animate-bounce"
            >
              <span class="material-symbols-outlined text-secondary text-3xl mb-1">shopping_bag</span>
              <span class="font-serif text-xl font-bold text-on-secondary-container">Ready for Pickup</span>
            </div>
          </div>
        </section>

        <%!-- Main Bento Grid Content --%>
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-8">
          <%!-- Left Column: Progress & Timeline (8 Columns) --%>
          <div class="lg:col-span-8 flex flex-col gap-8">
            <%!-- Progress Visual Card --%>
            <div class="bg-surface-container-low p-8 rounded-xl relative overflow-hidden shadow-sm">
              <div class="absolute top-0 right-0 w-32 h-32 opacity-5 pointer-events-none">
                <span class="material-symbols-outlined text-[120px]">local_pizza</span>
              </div>

              <div class="relative z-10">
                <div class="flex items-center gap-3 mb-8">
                  <span class={[
                    "inline-flex items-center justify-center px-3 py-1 rounded-full text-[0.7rem] font-bold tracking-wider uppercase shadow-sm",
                    status_badge_bg(@order.status)
                  ]}>
                    <span
                      class="material-symbols-outlined text-sm mr-1"
                      style="font-variation-settings: 'FILL' 1;"
                    >
                      {status_icon(@order.status)}
                    </span>
                    {status_label(@order.status)}
                  </span>
                  <span class="text-on-surface-variant text-sm font-medium italic">
                    {status_subheading(@order.status)}
                  </span>
                </div>

                <%!-- Progress Bar Visual --%>
                <div :if={@order.status != :cancelled} class="relative py-4">
                  <%!-- Track line --%>
                  <div class="absolute top-1/2 left-0 w-full h-[2px] bg-surface-container-highest -translate-y-1/2 rounded-full">
                  </div>
                  <div
                    class="absolute top-1/2 left-0 h-[2px] bg-primary transition-all duration-1000 -translate-y-1/2 rounded-full"
                    style={"width: #{status_progress_percent(@order.status)}%;"}
                  >
                  </div>

                  <div class="relative flex justify-between">
                    <%!-- Step 1: Received --%>
                    <.progress_step
                      label="Received"
                      icon="receipt_long"
                      active={status_step_active?(@order.status, 1)}
                      completed={status_step_completed?(@order.status, 1)}
                    />
                    <%!-- Step 2: Preparing --%>
                    <.progress_step
                      label="Preparing"
                      icon="skillet"
                      active={status_step_active?(@order.status, 2)}
                      completed={status_step_completed?(@order.status, 2)}
                    />
                    <%!-- Step 3: Ready --%>
                    <.progress_step
                      label="Ready"
                      icon="shopping_bag"
                      active={status_step_active?(@order.status, 3)}
                      completed={status_step_completed?(@order.status, 3)}
                    />
                    <%!-- Step 4: Arrived/Enjoy --%>
                    <.progress_step
                      label="Enjoy"
                      icon="restaurant"
                      active={status_step_active?(@order.status, 4)}
                      completed={status_step_completed?(@order.status, 4)}
                    />
                  </div>
                </div>
              </div>
            </div>

            <%!-- Opt-in to browser notifications --%>
            <div
              :if={@order.status not in [:completed, :cancelled]}
              id="notification-prompt"
              phx-hook="OrderNotifications"
              data-public-key={@vapid_public_key}
              class="hidden bg-surface-container-lowest p-6 rounded-xl shadow-sm border border-outline-variant/10 flex items-center justify-between"
            >
              <div class="flex items-center gap-4">
                <div class="p-2 bg-secondary-container text-on-secondary-container rounded-lg">
                  <span class="material-symbols-outlined">notifications</span>
                </div>
                <div>
                  <p class="font-serif text-sm font-bold text-on-surface">Get Notified</p>
                  <p class="text-[0.7rem] text-on-surface-variant">
                    We'll alert you when your order is ready
                  </p>
                </div>
              </div>
              <button
                id="notification-btn"
                class="bg-white text-on-surface border border-outline-variant/30 px-6 py-2.5 rounded-md text-[0.65rem] font-bold uppercase tracking-widest hover:bg-surface-container-low transition-all active:scale-95 shadow-sm"
              >
                Enable
              </button>
            </div>

            <%!-- Timeline List --%>
            <div class="flex flex-col gap-4">
              <h3 class="font-serif text-xl font-bold px-1 italic">Timeline</h3>
              <div class="space-y-3">
                <div class="flex items-start gap-4 p-4 rounded-xl bg-surface-container-lowest shadow-sm border border-outline-variant/5">
                  <div class="w-8 h-8 rounded-full bg-secondary-container flex items-center justify-center text-on-secondary-container shrink-0">
                    <span class="material-symbols-outlined text-sm">receipt_long</span>
                  </div>
                  <div class="flex-1 min-w-0 pt-0.5">
                    <p class="font-serif text-sm font-bold text-on-surface">Order Placed</p>
                    <p class="text-[0.65rem] text-on-surface-variant uppercase tracking-wider font-medium">
                      {format_time(@order.inserted_at)}
                    </p>
                  </div>
                </div>

                <%= for update <- Enum.reverse(@order.order_updates || []) do %>
                  <div class={[
                    "flex items-start gap-4 p-4 rounded-xl shadow-sm border border-outline-variant/5 transition-all duration-300",
                    if(update.message,
                      do: "bg-primary-container text-on-primary-container",
                      else: "bg-surface-container-lowest")
                  ]}>
                    <div class={[
                      "w-8 h-8 rounded-full flex items-center justify-center shrink-0 shadow-sm",
                      if(update.message,
                        do: "bg-white text-primary",
                        else: "bg-surface-container-highest text-on-surface-variant")
                    ]}>
                      <span class="material-symbols-outlined text-sm">
                        {if update.message, do: "chat_bubble", else: status_timeline_icon(update.status)}
                      </span>
                    </div>
                    <div class="flex-1 min-w-0 pt-0.5">
                      <p class="font-serif text-sm font-bold">
                        {if update.message, do: update.message, else: timeline_label(update.status)}
                      </p>
                      <p class="text-[0.65rem] opacity-70 uppercase tracking-wider font-medium">
                        {format_time(update.inserted_at)}
                      </p>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Right Column: Summary (4 Columns) --%>
          <aside class="lg:col-span-4 flex flex-col gap-6">
            <div class="bg-surface-container-lowest p-8 rounded-xl shadow-sm border border-outline-variant/10 flex-1">
              <h3 class="font-serif text-2xl font-bold mb-8 border-b border-surface-container-low pb-4">
                Order Summary
              </h3>
              <div class="space-y-6">
                <%= for item <- (@order.order_items || []) do %>
                  <div class="flex justify-between items-start">
                    <div class="flex gap-4 min-w-0">
                      <span class="font-serif text-lg font-bold text-primary shrink-0">
                        {item.quantity}x
                      </span>
                      <div class="min-w-0">
                        <p class="font-bold text-sm truncate">{item.item_name}</p>
                        <p
                          :if={item.size_snapshot}
                          class="text-[0.65rem] uppercase tracking-widest text-secondary font-bold mt-0.5"
                        >
                          {item.size_snapshot["name"]}
                        </p>
                        <p
                          :for={mod <- (item.modifiers_snapshot || [])}
                          class="text-xs text-on-surface-variant italic leading-tight"
                        >
                          + {mod["name"]}
                        </p>
                      </div>
                    </div>
                    <span class="text-sm font-medium shrink-0 ml-4">
                      {format_money(Money.mult!(item.price_at_time, item.quantity))}
                    </span>
                  </div>
                <% end %>
              </div>

              <div class="mt-12 pt-6 border-t border-surface-container-low space-y-3">
                <div class="flex justify-between text-lg font-bold mt-4 pt-4 border-t border-surface-container-low text-on-surface">
                  <span class="font-serif">Total</span>
                  <span class="font-serif">{format_money(@order.total_price)}</span>
                </div>
              </div>

              <div class="mt-8">
                <.link
                  navigate={~p"/menu/#{@org.slug}"}
                  class="w-full bg-gradient-to-br from-primary to-primary-container text-white py-4 rounded-md text-[0.65rem] font-bold uppercase tracking-[0.2em] shadow-lg shadow-primary/10 hover:opacity-90 active:scale-[0.98] transition-all flex items-center justify-center"
                >
                  Order More
                </.link>
              </div>
            </div>

            <div
              :if={@order.notes && @order.notes != ""}
              class="bg-primary/5 p-6 rounded-xl border border-primary/10 shadow-sm"
            >
              <div class="flex gap-4 items-start">
                <div class="p-2 bg-primary/10 rounded-lg text-primary">
                  <span class="material-symbols-outlined">restaurant</span>
                </div>
                <div>
                  <p class="font-serif text-sm font-bold text-on-surface">Atelier Notes</p>
                  <p class="text-[0.65rem] text-on-surface-variant leading-relaxed mt-1">
                    {@order.notes}
                  </p>
                </div>
              </div>
            </div>

            <%!-- Back link --%>
            <div class="text-center">
              <.link
                navigate={~p"/menu/#{@org.slug}"}
                class="font-body text-xs text-on-surface-variant hover:text-on-surface transition-colors underline underline-offset-4 uppercase tracking-widest font-bold"
              >
                Back to menu
              </.link>
            </div>
          </aside>
        </div>
      </main>

      <%!-- Background Elements --%>
      <div class="fixed top-[15%] right-[-30px] opacity-[0.03] pointer-events-none transform rotate-[25deg] select-none hidden lg:block text-on-surface z-[-1]">
        <span class="material-symbols-outlined" style="font-size: 180px;">local_pizza</span>
      </div>
      <div class="fixed bottom-[20%] left-[-40px] opacity-[0.04] pointer-events-none transform -rotate-[15deg] select-none hidden lg:block text-on-surface z-[-1]">
        <span class="material-symbols-outlined" style="font-size: 200px;">egg</span>
      </div>
      <div class="fixed top-[45%] left-[-20px] opacity-[0.02] pointer-events-none transform rotate-[10deg] select-none hidden lg:block text-on-surface z-[-1]">
        <span class="material-symbols-outlined" style="font-size: 140px;">spa</span>
      </div>
      <div class="fixed bottom-[10%] right-[-10px] opacity-[0.03] pointer-events-none transform -rotate-[20deg] select-none hidden lg:block text-on-surface z-[-1]">
        <span class="material-symbols-outlined" style="font-size: 160px;">skillet</span>
      </div>
      <div
        class="fixed inset-0 pointer-events-none opacity-[0.02] mix-blend-multiply z-[-1]"
        style="background-image: url('https://www.transparenttextures.com/patterns/handmade-paper.png');"
      >
      </div>
    </div>
    """
  end

  defp progress_step(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-3 relative">
      <div class={[
        "z-10 transition-all duration-500",
        @active && "w-12 h-12 -mt-1 rounded-full bg-white border-4 border-primary flex items-center justify-center shadow-xl",
        !@active && @completed && "w-10 h-10 rounded-full bg-primary text-white flex items-center justify-center shadow-lg shadow-primary/20",
        !@active && !@completed && "w-10 h-10 rounded-full bg-surface-container-highest text-stone-400 flex items-center justify-center"
      ]}>
        <span class={[
          "material-symbols-outlined text-lg",
          @active && "text-primary font-bold animate-pulse",
          !@active && @completed && "text-white",
          !@active && !@completed && "opacity-40"
        ]}>
          {if @completed && !@active, do: "check", else: @icon}
        </span>
      </div>
      <span class={[
        "font-label text-[0.65rem] uppercase font-bold tracking-tighter transition-colors",
        @active && "text-primary",
        @completed && !@active && "text-on-surface",
        !@active && !@completed && "text-stone-400"
      ]}>
        {@label}
      </span>
    </div>
    """
  end

  defp order_number(order) do
    order.id |> String.slice(-4, 4) |> String.upcase()
  end

  defp status_headline(:pending), do: "Your order is received."
  defp status_headline(:confirmed), do: "Your pie is in the fire."
  defp status_headline(:preparing), do: "The dough is dancing."
  defp status_headline(:ready), do: "Hot and fresh for you."
  defp status_headline(:completed), do: "Hope you enjoyed it!"
  defp status_headline(:cancelled), do: "Order cancelled."

  defp status_label(:pending), do: "Received"
  defp status_label(:confirmed), do: "Confirmed"
  defp status_label(:preparing), do: "Preparing"
  defp status_label(:ready), do: "Ready"
  defp status_label(:completed), do: "Enjoy"
  defp status_label(:cancelled), do: "Cancelled"

  defp status_badge_bg(:ready), do: "bg-secondary-container text-on-secondary-container"
  defp status_badge_bg(:completed), do: "bg-surface-container-highest text-on-surface-variant"
  defp status_badge_bg(:cancelled), do: "bg-error-container text-on-error-container"
  defp status_badge_bg(:preparing), do: "bg-primary-container text-on-primary-container"
  defp status_badge_bg(_), do: "bg-surface-container-high text-on-surface-variant"

  defp status_progress_percent(:pending), do: 5
  defp status_progress_percent(:confirmed), do: 25
  defp status_progress_percent(:preparing), do: 50
  defp status_progress_percent(:ready), do: 85
  defp status_progress_percent(:completed), do: 100
  defp status_progress_percent(_), do: 0

  defp status_step_active?(:pending, 1), do: true
  defp status_step_active?(:confirmed, 1), do: true
  defp status_step_active?(:preparing, 2), do: true
  defp status_step_active?(:ready, 3), do: true
  defp status_step_active?(:completed, 4), do: true
  defp status_step_active?(_, _), do: false

  defp status_step_completed?(:confirmed, 1), do: true

  defp status_step_completed?(status, step) do
    order = [:pending, :confirmed, :preparing, :ready, :completed]
    current_idx = Enum.find_index(order, &(&1 == status)) || -1

    case step do
      1 -> current_idx >= 1
      2 -> current_idx >= 2
      3 -> current_idx >= 3
      4 -> current_idx >= 4
      _ -> false
    end
  end

  defp status_icon(:ready), do: "check_circle"
  defp status_icon(:completed), do: "done_all"
  defp status_icon(:cancelled), do: "cancel"
  defp status_icon(:preparing), do: "skillet"
  defp status_icon(:confirmed), do: "thumb_up"
  defp status_icon(_), do: "receipt_long"

  defp status_subheading(:pending), do: "Waiting for the kitchen to confirm"
  defp status_subheading(:confirmed), do: "The kitchen has your order"
  defp status_subheading(:preparing), do: "Your food is being made fresh"
  defp status_subheading(:ready), do: "Head to the counter to pick it up"
  defp status_subheading(:completed), do: "Thanks for your order!"
  defp status_subheading(:cancelled), do: "Please speak to the kitchen"

  defp status_timeline_icon(:confirmed), do: "thumb_up"
  defp status_timeline_icon(:preparing), do: "skillet"
  defp status_timeline_icon(:ready), do: "check_circle"
  defp status_timeline_icon(:completed), do: "done_all"
  defp status_timeline_icon(:cancelled), do: "cancel"
  defp status_timeline_icon(_), do: "radio_button_checked"

  defp timeline_label(:confirmed), do: "Order confirmed"
  defp timeline_label(:preparing), do: "Now preparing"
  defp timeline_label(:ready), do: "Ready for pickup!"
  defp timeline_label(:completed), do: "Order complete"
  defp timeline_label(:cancelled), do: "Order cancelled"
  defp timeline_label(_), do: "Status updated"

  defp format_time(nil), do: ""

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end

  defp format_date(nil), do: ""

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp format_money(money) do
    Money.to_string!(money)
  rescue
    _ -> "#{money}"
  end
end
