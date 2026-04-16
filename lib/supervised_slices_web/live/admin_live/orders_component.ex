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
      |> assign(Map.drop(assigns, [:orders, :action, :flash]))

    socket =
      if orders = assigns[:orders] do
        stream(socket, :orders, orders, reset: true)
      else
        socket
      end

    {:ok, socket}
  end

  def handle_event("advance_order", %{"id" => order_id}, socket) do
    %{ash_scope: scope} = socket.assigns
    order = Order.get!(order_id, scope: scope)
    new_status = next_status(order.status)
    Order.update_status!(order, %{status: new_status}, scope: scope)
    distinct_id = scope.current_user && scope.current_user.id
    SupervisedSlices.Analytics.capture("order_status_advanced", distinct_id, %{
      order_id: order_id,
      from_status: order.status,
      to_status: new_status,
      "$groups": %{organization: socket.assigns.org.id}
    })
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
    <div class="space-y-3">
      <div class="flex items-center justify-between px-2 pb-1">
        <h2 class="font-headline text-xl font-bold text-on-surface">
          Live Queue
        </h2>
        <span class="text-xs font-bold uppercase tracking-widest text-on-surface-variant/40">
          Oldest first
        </span>
      </div>

      <div
        id="orders"
        phx-update="stream"
        class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-8 items-start"
      >
        <%= for {dom_id, order} <- @streams.orders do %>
          <div
            id={dom_id}
            class={[
              "bg-surface-container-low rounded-md flex flex-col shadow-sm border-t-4 overflow-hidden transition-all duration-500",
              status_border_class(order.status),
              if(order.status == :pending, do: "ring-primary ring-offset-2"),
              urgency_ring_class(order)
            ]}
            style={urgency_style(order)}
          >
            <%!-- Header --%>
            <div class="p-5 flex justify-between items-start">
              <div>
                <h3 class="text-xl font-black tracking-tight font-headline text-on-surface">
                  #{order_number(order)}
                </h3>
                <p class="text-[0.65rem] uppercase font-bold tracking-widest text-on-surface-variant/60">
                  {time_ago(order.inserted_at)}
                </p>
                <div class="mt-1 font-body text-xs font-bold text-on-surface truncate max-w-[120px]">
                  {order.customer_name}
                </div>
              </div>
              <span class={[
                "text-[0.6rem] font-black px-3 py-1.5 rounded-sm tracking-[0.2em] uppercase flex items-center gap-2 transition-all duration-500",
                status_badge_class(order.status),
                if(order.status == :pending, do: "scale-110 shadow-md animate-pulse")
              ]}>
                <%= if order.status == :pending do %>
                  <span class="relative flex h-2.5 w-2.5">
                    <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-white opacity-75">
                    </span>
                    <span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-white"></span>
                  </span>
                <% end %>
                {status_label(order.status)}
              </span>
            </div>

            <%!-- Items --%>
            <div class="px-5 pb-6 space-y-4 flex-grow">
              <div class="space-y-4">
                <%= for item <- (order.order_items || []) do %>
                  <div class="space-y-2">
                    <div class="flex justify-between items-start">
                      <span class="text-sm font-bold text-on-surface leading-tight">
                        {item.quantity}x
                        <%= if item.size_snapshot do %>
                          {item.size_snapshot["name"]}
                        <% end %>
                        {item.item_name}
                      </span>
                    </div>
                    <%= if item.modifiers_snapshot && length(item.modifiers_snapshot) > 0 do %>
                      <div class="flex flex-wrap gap-1">
                        <%= for mod <- item.modifiers_snapshot do %>
                          <span class="bg-surface-container-highest text-[0.65rem] px-2 py-0.5 rounded-sm font-bold text-on-surface-variant uppercase">
                            {mod["name"]}
                          </span>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <%= if order.notes && order.notes != "" do %>
                <div class="pt-4 border-t border-on-surface/5">
                  <p class="text-[11px] text-on-surface-variant leading-relaxed">
                    <span class="font-bold text-[9px] uppercase tracking-widest block mb-1 opacity-40">
                      Notes
                    </span>
                    {order.notes}
                  </p>
                </div>
              <% end %>
            </div>

            <%!-- Actions --%>
            <div class="p-4 bg-surface-container flex flex-col gap-2">
              <%= if next_status_label(order.status) do %>
                <button
                  phx-click="advance_order"
                  phx-value-id={order.id}
                  phx-target={@myself}
                  class={[
                    "w-full py-3 rounded-md font-bold text-xs uppercase tracking-[0.1em] transition-all active:scale-[0.98]",
                    action_button_class(order.status)
                  ]}
                >
                  {next_status_label(order.status)}
                </button>
              <% end %>

              <div class="flex gap-2">
                <%= if order.status not in [:completed, :cancelled] do %>
                  <button
                    phx-click="cancel_order"
                    phx-value-id={order.id}
                    phx-target={@myself}
                    class="flex-1 py-2 text-[9px] font-bold uppercase tracking-widest text-on-surface-variant/40 hover:text-error transition-colors text-center"
                  >
                    Cancel
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
                        class="px-2 py-2 rounded bg-surface-container-highest/50 text-on-surface-variant text-[9px] font-black uppercase tracking-widest hover:bg-secondary-container hover:text-on-secondary-container transition-colors"
                      >
                        {msg}
                      </button>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <div
        id="orders-empty"
        class="hidden only:flex flex-col items-center py-24 text-on-surface-variant/20"
      >
        <span class="material-symbols-outlined text-8xl">receipt_long</span>
        <p class="mt-4 text-xl font-black font-headline uppercase tracking-widest opacity-40">
          No active orders
        </p>
      </div>
    </div>
    """
  end

  defp urgency_level(order) do
    if order.status == :pending do
      # Reach max urgency at 10 minutes
      seconds = DateTime.diff(DateTime.utc_now(), order.inserted_at, :second)
      min(seconds, 600) / 600
    else
      0
    end
  end

  defp urgency_ring_class(order) do
    if order.status == :pending do
      level = urgency_level(order)

      cond do
        level > 0.8 -> "ring-4"
        level > 0.5 -> "ring-2"
        level > 0.2 -> "ring-1"
        true -> ""
      end
    else
      ""
    end
  end

  defp urgency_style(order) do
    if order.status == :pending do
      level = urgency_level(order)
      "box-shadow: 0 0 #{level * 20}px rgba(140, 22, 26, #{0.1 + level * 0.2});"
    else
      nil
    end
  end

  defp next_status(:pending), do: :confirmed
  defp next_status(:confirmed), do: :preparing
  defp next_status(:preparing), do: :ready
  defp next_status(:ready), do: :completed
  defp next_status(s), do: s

  defp next_status_label(:pending), do: "Confirm Order"
  defp next_status_label(:confirmed), do: "Start Prep"
  defp next_status_label(:preparing), do: "Mark Ready"
  defp next_status_label(:ready), do: "Handed Over"
  defp next_status_label(_), do: nil

  defp time_ago(nil), do: ""

  defp time_ago(datetime) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      seconds < 60 -> "Just arrived"
      seconds < 3600 -> "Ordered #{div(seconds, 60)}m ago"
      true -> "Ordered #{div(seconds, 3600)}h ago"
    end
  end

  defp order_number(order) do
    order.id |> String.slice(-4, 4) |> String.upcase() |> then(&"##{&1}")
  end

  defp status_border_class(:pending), do: "border-primary"
  defp status_border_class(:confirmed), do: "border-secondary"
  defp status_border_class(:preparing), do: "border-secondary"
  defp status_border_class(:ready), do: "border-on-secondary-container"
  defp status_border_class(_), do: "border-surface-container"

  defp status_badge_class(:pending), do: "bg-primary text-white"
  defp status_badge_class(:confirmed), do: "bg-secondary text-white"
  defp status_badge_class(:preparing), do: "bg-secondary text-white"
  defp status_badge_class(:ready), do: "bg-secondary-container text-on-secondary-container"
  defp status_badge_class(_), do: "bg-surface-container text-on-surface-variant"

  defp action_button_class(:pending), do: "bg-primary text-white hover:opacity-90"

  defp action_button_class(:confirmed),
    do: "border-2 border-secondary text-secondary hover:bg-secondary hover:text-white"

  defp action_button_class(:preparing),
    do: "border-2 border-secondary text-secondary hover:bg-secondary hover:text-white"

  defp action_button_class(:ready), do: "bg-on-secondary-container text-white hover:opacity-90"
  defp action_button_class(_), do: "bg-surface-container-highest text-on-surface"

  defp status_label(:pending), do: "NEW"
  defp status_label(:confirmed), do: "CONFIRMED"
  defp status_label(:preparing), do: "PREPARING"
  defp status_label(:ready), do: "READY"
  defp status_label(:completed), do: "DONE"
  defp status_label(:cancelled), do: "CANCELLED"
end
