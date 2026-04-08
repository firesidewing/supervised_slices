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

    {:ok,
     socket
     |> assign(:order, order)
     |> assign(:estimated_at, estimated_at)
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

  def render(assigns) do
    assigns = assign(assigns, :estimated_unix, DateTime.to_unix(assigns.estimated_at))

    ~H"""
    <div class="min-h-screen bg-surface px-4 py-10 max-w-xl mx-auto">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-8">
        <h1 class="font-headline text-xl font-bold text-primary">{@org.name}</h1>
        <span class="font-body text-sm font-bold text-on-surface-variant bg-surface-container-low px-4 py-1.5 rounded-full uppercase tracking-widest">
          #{order_number(@order)}
        </span>
      </div>

      <%!-- Status hero card --%>
      <div class={[
        "rounded-xl p-8 text-center mb-8",
        status_card_bg(@order.status)
      ]}>
        <div class="flex justify-center mb-4">
          <span class="material-symbols-outlined text-5xl">{status_icon(@order.status)}</span>
        </div>
        <h2 class="font-headline text-2xl font-black text-on-surface mb-1">
          {status_heading(@order.status)}
        </h2>
        <p class="font-body text-sm text-on-surface-variant mb-6">
          {status_subheading(@order.status)}
        </p>

        <%!-- ETA countdown (hidden once order is ready/completed/cancelled) --%>
        <div
          :if={@order.status not in [:ready, :completed, :cancelled]}
          id="order-countdown"
          phx-hook="Countdown"
          data-estimated-at={@estimated_unix}
          data-status={@order.status}
          class="bg-surface-container-lowest rounded-xl px-6 py-4 inline-block min-w-[200px]"
        >
          <p class="font-body text-xs uppercase tracking-widest text-on-surface-variant mb-1">
            Estimated wait
          </p>
          <p class="font-headline text-lg font-bold text-on-surface">
            Calculating...
          </p>
        </div>
      </div>

      <%!-- Opt-in to browser notifications --%>
      <div
        :if={@order.status not in [:completed, :cancelled]}
        id="notification-prompt"
        phx-hook="OrderNotifications"
        class="bg-surface-container-low rounded-xl px-5 py-4 flex items-center justify-between mb-8"
      >
        <div>
          <p class="font-body text-sm font-bold text-on-surface">Get notified</p>
          <p class="font-body text-xs text-on-surface-variant">
            We'll alert you when your order is ready
          </p>
        </div>
        <button
          id="notification-btn"
          class="font-body text-xs font-bold uppercase tracking-widest px-4 py-2 rounded-full bg-secondary text-on-secondary hover:opacity-90 transition-opacity active:scale-95"
        >
          Enable
        </button>
      </div>

      <%!-- Timeline --%>
      <div class="mb-8">
        <h3 class="font-body text-xs font-bold uppercase tracking-widest text-on-surface-variant mb-4 px-1">
          Timeline
        </h3>
        <div class="space-y-1">
          <div class={[
            "flex items-start gap-3 px-4 py-3 rounded-xl",
            "bg-surface-container-lowest"
          ]}>
            <span class="material-symbols-outlined text-base text-secondary mt-0.5">
              receipt_long
            </span>
            <div class="flex-1 min-w-0">
              <p class="font-body text-sm font-bold text-on-surface">Order placed</p>
              <p class="font-body text-xs text-on-surface-variant">
                {format_time(@order.inserted_at)}
              </p>
            </div>
          </div>

          <%= for update <- (@order.order_updates || []) do %>
            <div class={[
              "flex items-start gap-3 px-4 py-3 rounded-xl",
              if(update.message, do: "bg-secondary-container/30", else: "bg-surface-container-lowest")
            ]}>
              <span class={[
                "material-symbols-outlined text-base mt-0.5",
                if(update.message, do: "text-secondary", else: update_icon_color(update.status))
              ]}>
                {if update.message, do: "chat_bubble", else: status_timeline_icon(update.status)}
              </span>
              <div class="flex-1 min-w-0">
                <p class="font-body text-sm font-bold text-on-surface">
                  {if update.message, do: update.message, else: timeline_label(update.status)}
                </p>
                <%= if update.message do %>
                  <p class="font-body text-xs text-secondary font-medium">Kitchen update</p>
                <% end %>
                <p class="font-body text-xs text-on-surface-variant">
                  {format_time(update.inserted_at)}
                </p>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Order summary --%>
      <div class="bg-surface-container-lowest rounded-xl p-6">
        <h3 class="font-body text-xs font-bold uppercase tracking-widest text-on-surface-variant mb-4">
          Your order
        </h3>
        <div class="space-y-2 mb-4">
          <%= for item <- (@order.order_items || []) do %>
            <div class="flex items-center justify-between">
              <span class="font-body text-sm text-on-surface">
                <span class="font-bold text-primary">{item.quantity}×</span> {item.item_name}
              </span>
              <span class="font-body text-sm font-bold text-on-surface">
                {format_money(Money.mult!(item.price_at_time, item.quantity))}
              </span>
            </div>
          <% end %>
        </div>
        <div class="flex items-center justify-between pt-3 border-t border-surface-container-low">
          <span class="font-headline text-sm font-bold text-on-surface">Total</span>
          <span class="font-headline text-base font-black text-primary">
            {format_money(@order.total_price)}
          </span>
        </div>
      </div>

      <%!-- Back to menu --%>
      <div class="mt-8 text-center">
        <.link
          navigate={~p"/menu/#{@org.slug}"}
          class="font-body text-sm text-on-surface-variant hover:text-on-surface transition-colors underline underline-offset-4"
        >
          Back to menu
        </.link>
      </div>
    </div>
    """
  end

  defp order_number(order) do
    order.id |> String.slice(-4, 4) |> String.upcase()
  end

  defp status_card_bg(:ready), do: "bg-secondary-fixed"
  defp status_card_bg(:completed), do: "bg-secondary-fixed"
  defp status_card_bg(:cancelled), do: "bg-surface-container-low"
  defp status_card_bg(:preparing), do: "bg-tertiary-fixed"
  defp status_card_bg(_), do: "bg-primary-fixed"

  defp status_icon(:ready), do: "check_circle"
  defp status_icon(:completed), do: "done_all"
  defp status_icon(:cancelled), do: "cancel"
  defp status_icon(:preparing), do: "skillet"
  defp status_icon(:confirmed), do: "thumb_up"
  defp status_icon(_), do: "receipt_long"

  defp status_heading(:pending), do: "Order received!"
  defp status_heading(:confirmed), do: "Order confirmed"
  defp status_heading(:preparing), do: "Preparing your order"
  defp status_heading(:ready), do: "Ready for pickup!"
  defp status_heading(:completed), do: "Order complete"
  defp status_heading(:cancelled), do: "Order cancelled"

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

  defp update_icon_color(:ready), do: "text-secondary"
  defp update_icon_color(:completed), do: "text-secondary"
  defp update_icon_color(:cancelled), do: "text-error"
  defp update_icon_color(:preparing), do: "text-tertiary"
  defp update_icon_color(_), do: "text-primary"

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

  defp format_money(money) do
    Money.to_string!(money)
  rescue
    _ -> "#{money}"
  end
end
