defmodule SupervisedSlicesWeb.AdminLive.OrdersComponent do
  use SupervisedSlicesWeb, :live_component

  alias SupervisedSlices.Orders.Order

  def mount(socket) do
    {:ok, stream(socket, :orders, [])}
  end

  def update(%{action: {:insert, order}}, socket) do
    {:ok, stream_insert(socket, :orders, order, at: 0)}
  end

  def update(%{action: {:update, order}}, socket) do
    {:ok, stream_insert(socket, :orders, order)}
  end

  def update(%{action: {:delete, order}}, socket) do
    {:ok, stream_delete(socket, :orders, order)}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(:id, assigns.id)
      |> assign(:active_carts_count, assigns.active_carts_count)
      |> assign(:visitor_count, assigns.visitor_count)
      |> assign(:ash_scope, assigns.ash_scope)
      |> stream(:orders, assigns.orders, reset: true)

    {:ok, socket}
  end

  def handle_event("advance_order", %{"id" => order_id}, socket) do
    %{ash_scope: scope} = socket.assigns
    order = Order.get!(order_id, scope: scope)
    Order.update_status!(order, %{status: next_status(order.status)}, scope: scope)
    {:noreply, socket}
  end

  def handle_event("cancel_order", %{"id" => order_id}, socket) do
    %{ash_scope: scope} = socket.assigns
    order = Order.get!(order_id, scope: scope)
    Order.update_status!(order, %{status: :cancelled}, scope: scope)
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <section class="p-8 space-y-8">
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div class="bg-surface-container-low rounded-xl p-8 flex flex-col justify-center">
          <span
            class="text-xs uppercase tracking-widest font-bold text-on-surface-variant mb-2"
            style="font-family: 'Be Vietnam Pro', sans-serif;"
          >
            Active Tickets
          </span>
          <span
            class="text-4xl font-black text-on-surface"
            style="font-family: 'Plus Jakarta Sans', sans-serif;"
            id="active-tickets-count"
          >
            &mdash;
          </span>
        </div>
        <div class="bg-secondary-container/30 rounded-xl p-8 flex flex-col justify-center">
          <span
            class="text-xs uppercase tracking-widest font-bold text-secondary mb-2"
            style="font-family: 'Be Vietnam Pro', sans-serif;"
          >
            Customers Browsing
          </span>
          <span
            class="text-4xl font-black text-secondary"
            style="font-family: 'Plus Jakarta Sans', sans-serif;"
          >
            {@visitor_count}
          </span>
        </div>
        <div class="bg-primary-container rounded-xl p-8 flex flex-col justify-center">
          <span
            class="text-xs uppercase tracking-widest font-bold text-on-primary-container/70 mb-2"
            style="font-family: 'Be Vietnam Pro', sans-serif;"
          >
            Active Baskets
          </span>
          <span
            class="text-4xl font-black text-on-primary-container italic"
            style="font-family: 'Plus Jakarta Sans', sans-serif;"
          >
            {@active_carts_count}
          </span>
        </div>
      </div>

      <div class="space-y-3">
        <div class="flex items-center justify-between px-2 pb-1">
          <h2
            class="text-xl font-bold text-on-surface"
            style="font-family: 'Plus Jakarta Sans', sans-serif;"
          >
            Live Queue
          </h2>
          <span class="text-sm text-on-surface-variant">Oldest first</span>
        </div>

        <div id="orders" phx-update="stream" class="space-y-3">
          <%= for {dom_id, order} <- @streams.orders do %>
            <div
              id={dom_id}
              class="bg-surface-container-lowest rounded-xl p-6 flex flex-col lg:flex-row lg:items-center justify-between gap-6 hover:scale-[1.005] transition-transform duration-200"
            >
              <div class="flex items-start gap-5 min-w-0">
                <div class="bg-surface-container-low w-16 h-16 shrink-0 rounded-xl flex items-center justify-center">
                  <span
                    class="text-lg font-black text-on-surface"
                    style="font-family: 'Plus Jakarta Sans', sans-serif;"
                  >
                    #{order_number(order)}
                  </span>
                </div>
                <div class="min-w-0">
                  <h3
                    class="text-base font-bold text-on-surface truncate"
                    style="font-family: 'Plus Jakarta Sans', sans-serif;"
                  >
                    {order.customer_name}
                  </h3>
                  <p class="text-sm text-on-surface-variant">{time_ago(order.inserted_at)}</p>
                  <%= if order.notes && order.notes != "" do %>
                    <p class="text-xs text-on-surface-variant mt-1 italic">"{order.notes}"</p>
                  <% end %>
                </div>
              </div>

              <div class="flex-1 px-2 min-w-0">
                <div class="flex flex-wrap gap-2">
                  <%= for item <- (order.order_items || []) do %>
                    <span
                      class="bg-surface-container px-3 py-1 rounded-full text-xs font-bold text-on-surface uppercase tracking-wider"
                      style="font-family: 'Be Vietnam Pro', sans-serif;"
                    >
                      {item.quantity}x {item.item_name}
                    </span>
                  <% end %>
                </div>
                <div class="mt-2 text-sm font-bold text-primary">
                  {format_money(order.total_price)}
                </div>
              </div>

              <div class="flex items-center gap-4 shrink-0">
                <div class={[
                  "flex items-center gap-2 px-4 py-2 rounded-full text-xs font-bold uppercase tracking-widest",
                  status_badge_class(order.status)
                ]}>
                  <%= if order.status == :pending do %>
                    <span class="w-1.5 h-1.5 rounded-full bg-primary animate-pulse"></span>
                  <% end %>
                  {status_label(order.status)}
                </div>

                <%= if next_status_label(order.status) do %>
                  <button
                    phx-click="advance_order"
                    phx-value-id={order.id}
                    phx-target={@myself}
                    class={[
                      "px-6 py-2.5 rounded-xl font-bold transition-all active:scale-95 duration-150",
                      if(order.status == :ready,
                        do: "bg-primary text-white hover:opacity-90 shadow-lg shadow-primary/20",
                        else:
                          "bg-surface-container-highest text-on-surface hover:bg-surface-container-high"
                      )
                    ]}
                    style="font-family: 'Plus Jakarta Sans', sans-serif;"
                  >
                    {next_status_label(order.status)}
                  </button>
                <% end %>

                <%= if order.status not in [:completed, :cancelled] do %>
                  <button
                    phx-click="cancel_order"
                    phx-value-id={order.id}
                    phx-target={@myself}
                    class="w-9 h-9 flex items-center justify-center rounded-full text-on-surface-variant hover:bg-error-container hover:text-error transition-colors"
                    title="Cancel order"
                  >
                    <span class="material-symbols-outlined" style="font-size: 18px;">close</span>
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <div
          id="orders-empty"
          class="hidden only:flex flex-col items-center py-20 text-on-surface-variant"
        >
          <span class="material-symbols-outlined text-6xl opacity-30">receipt_long</span>
          <p class="mt-4 text-lg font-medium">No active orders</p>
          <p class="text-sm opacity-60 mt-1">New orders will appear here in real-time</p>
        </div>
      </div>
    </section>
    """
  end

  defp next_status(:pending), do: :confirmed
  defp next_status(:confirmed), do: :preparing
  defp next_status(:preparing), do: :ready
  defp next_status(:ready), do: :completed
  defp next_status(s), do: s

  defp next_status_label(:pending), do: "Confirm"
  defp next_status_label(:confirmed), do: "Start Preparing"
  defp next_status_label(:preparing), do: "Mark Ready"
  defp next_status_label(:ready), do: "Complete"
  defp next_status_label(_), do: nil

  defp time_ago(nil), do: ""

  defp time_ago(datetime) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      true -> "#{div(seconds, 3600)}h ago"
    end
  end

  defp order_number(order) do
    order.id |> String.slice(-4, 4) |> String.upcase()
  end

  defp status_badge_class(:pending), do: "bg-primary-fixed text-on-primary-fixed-variant"
  defp status_badge_class(:confirmed), do: "bg-primary-fixed text-on-primary-fixed-variant"
  defp status_badge_class(:preparing), do: "bg-tertiary-fixed text-on-tertiary-fixed-variant"
  defp status_badge_class(:ready), do: "bg-secondary-fixed text-on-secondary-fixed-variant"
  defp status_badge_class(_), do: "bg-surface-container text-on-surface-variant"

  defp status_label(:pending), do: "New"
  defp status_label(:confirmed), do: "Confirmed"
  defp status_label(:preparing), do: "Preparing"
  defp status_label(:ready), do: "Ready"
  defp status_label(:completed), do: "Done"
  defp status_label(:cancelled), do: "Cancelled"

  defp format_money(money) do
    Money.to_string!(money)
  rescue
    _ -> "#{money}"
  end
end
