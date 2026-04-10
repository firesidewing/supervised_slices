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
      |> assign(:org, assigns.org)
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

  def handle_event("send_preset_update", %{"id" => order_id, "message" => message}, socket) do
    %{ash_scope: scope} = socket.assigns
    order = Order.get!(order_id, scope: scope)
    Order.send_update!(order, %{message: message}, scope: scope)
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <section class="p-8 space-y-8">
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div class="bg-surface-container-low rounded-xl p-8 flex flex-col justify-center">
          <span class="font-body text-xs uppercase tracking-widest font-bold text-on-surface-variant mb-2">
            Active Tickets
          </span>
          <span class="font-headline text-4xl font-black text-on-surface" id="active-tickets-count">
            &mdash;
          </span>
        </div>
        <div class="bg-secondary-container/30 rounded-xl p-8 flex flex-col justify-center">
          <span class="font-body text-xs uppercase tracking-widest font-bold text-secondary mb-2">
            Customers Browsing
          </span>
          <span class="font-headline text-4xl font-black text-secondary">
            {@visitor_count}
          </span>
        </div>
        <div class="bg-primary-container rounded-xl p-8 flex flex-col justify-center">
          <span class="font-body text-xs uppercase tracking-widest font-bold text-on-primary-container/70 mb-2">
            Active Baskets
          </span>
          <span class="font-headline text-4xl font-black text-on-primary-container italic">
            {@active_carts_count}
          </span>
        </div>
      </div>

      <div class="space-y-3">
        <div class="flex items-center justify-between px-2 pb-1">
          <h2 class="font-headline text-xl font-bold text-on-surface">
            Live Queue
          </h2>
          <span class="text-sm text-on-surface-variant">Oldest first</span>
        </div>

        <div
          id="orders"
          phx-update="stream"
          class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6"
        >
          <%= for {dom_id, order} <- @streams.orders do %>
            <div
              id={dom_id}
              class="bg-surface-container-lowest rounded-2xl flex flex-col hover:translate-y-[-2px] transition-all duration-300 shadow-[0_4px_20px_rgba(0,0,0,0.03)] border border-surface-container/10"
            >
              <%!-- Header --%>
              <div class="px-5 py-4 bg-surface-container-low/50 rounded-t-2xl flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <div class="bg-primary text-white w-9 h-9 rounded-lg flex items-center justify-center font-headline text-sm font-black italic">
                    #{order_number(order)}
                  </div>
                  <div class="min-w-0">
                    <h3 class="font-headline text-sm font-bold text-on-surface truncate leading-tight">
                      {order.customer_name}
                    </h3>
                    <p class="text-[10px] text-on-surface-variant font-medium tracking-wide">
                      {time_ago(order.inserted_at)}
                    </p>
                  </div>
                </div>
                <div class={[
                  "px-2.5 py-1 rounded-full text-[10px] font-bold uppercase tracking-widest",
                  status_badge_class(order.status)
                ]}>
                  {status_label(order.status)}
                </div>
              </div>

              <%!-- Items --%>
              <div class="flex-1 p-5 space-y-4">
                <div class="space-y-3">
                  <%= for item <- (order.order_items || []) do %>
                    <div class="flex flex-col gap-0.5">
                      <div class="font-body text-sm font-bold text-on-surface leading-tight">
                        <span class="text-primary tabular-nums font-black mr-0.5">{item.quantity}</span>x
                        <%= if item.size_snapshot do %>
                          <span class="text-sm font-bold text-secondary uppercase tracking-widest ml-1.5 mr-1.5">
                            {item.size_snapshot["name"]}
                          </span>
                        <% end %>
                        {item.item_name}
                      </div>
                      <%= for mod <- (item.modifiers_snapshot || []) do %>
                        <div class="text-[11px] text-on-surface-variant italic pl-6 opacity-75">
                          + {mod["name"]}
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>

                <%= if order.notes && order.notes != "" do %>
                  <div class="pt-3 border-t border-surface-container-low border-dashed">
                    <p class="text-[11px] text-on-surface-variant italic bg-surface-container-lowest p-2 rounded-lg">
                      <span class="font-bold text-[9px] uppercase tracking-widest block mb-1 opacity-50">
                        Notes:
                      </span>
                      "{order.notes}"
                    </p>
                  </div>
                <% end %>
              </div>

              <%!-- Actions --%>
              <div class="px-5 pb-5 pt-2 space-y-4">
                <div class="flex items-center justify-between text-on-surface pt-3 border-t border-surface-container-low border-dashed">
                  <span class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">
                    Total
                  </span>
                  <span class="text-base font-black italic tracking-tight">
                    {format_money(order.total_price)}
                  </span>
                </div>

                <div class="grid grid-cols-1 gap-2">
                  <%= if next_status_label(order.status) do %>
                    <button
                      phx-click="advance_order"
                      phx-value-id={order.id}
                      phx-target={@myself}
                      class={[
                        "w-full font-headline py-2.5 rounded-xl text-sm font-bold transition-all active:scale-[0.98] duration-150",
                        if(order.status == :ready,
                          do: "bg-primary text-white hover:opacity-90 shadow-lg shadow-primary/20",
                          else:
                            "bg-surface-container-highest text-on-surface hover:bg-surface-container-high"
                        )
                      ]}
                    >
                      {next_status_label(order.status)}
                    </button>
                  <% end %>

                  <div class="flex items-center gap-2">
                    <%= if order.status not in [:completed, :cancelled] do %>
                      <button
                        phx-click="cancel_order"
                        phx-value-id={order.id}
                        phx-target={@myself}
                        class="flex-1 flex items-center justify-center gap-1.5 py-2 text-[10px] font-bold uppercase tracking-widest text-on-surface-variant hover:bg-error-container/20 hover:text-error transition-colors rounded-lg"
                      >
                        <span class="material-symbols-outlined text-[16px]">close</span> Cancel
                      </button>
                    <% end %>

                    <%= if order.status in [:confirmed, :preparing] do %>
                      <div class="flex gap-1">
                        <%= for msg <- ["Behind", "5min"] do %>
                          <button
                            phx-click="send_preset_update"
                            phx-value-id={order.id}
                            phx-value-message={msg}
                            phx-target={@myself}
                            class="px-2 py-2 rounded-lg bg-surface-container-low text-on-surface-variant text-[9px] font-black uppercase tracking-widest hover:bg-secondary-container hover:text-on-secondary-container transition-colors"
                          >
                            {msg}
                          </button>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
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
