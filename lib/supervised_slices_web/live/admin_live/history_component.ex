defmodule SupervisedSlicesWeb.AdminLive.HistoryComponent do
  use SupervisedSlicesWeb, :live_component

  require Ash.Query

  alias SupervisedSlices.Orders.Order

  def update(assigns, socket) do
    socket =
      socket
      |> assign(:ash_scope, assigns.ash_scope)
      |> assign_new(:history_date, fn -> Date.utc_today() end)
      |> assign_new(:history_orders, fn ->
        load_history(assigns.ash_scope, Date.utc_today())
      end)

    {:ok, socket}
  end

  def handle_event("set_history_date", %{"date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        {:noreply,
         socket
         |> assign(:history_date, date)
         |> assign(:history_orders, load_history(socket.assigns.ash_scope, date))}

      _ ->
        {:noreply, socket}
    end
  end

  defp load_history(scope, date) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.add(start_dt, 86400, :second)

    Order
    |> Ash.Query.for_read(:completed, %{}, scope: scope, authorize?: false)
    |> Ash.Query.filter(inserted_at >= ^start_dt and inserted_at < ^end_dt)
    |> Ash.read!(authorize?: false)
  end

  defp format_money(nil), do: "-"
  defp format_money(%Money{} = m), do: Money.to_string!(m)

  defp order_number(order) do
    order.id |> String.slice(-4..-1)
  end

  defp total_revenue(orders) do
    orders
    |> Enum.reduce(Money.new!(:CAD, "0"), fn order, acc ->
      Money.add!(acc, order.total_price)
    end)
  end

  defp status_badge_class(:completed), do: "bg-secondary-container text-on-secondary-container"
  defp status_badge_class(:cancelled), do: "bg-surface-container-highest text-on-surface-variant"
  defp status_badge_class(_), do: "bg-surface-container text-on-surface-variant"

  defp status_label(:completed), do: "DONE"
  defp status_label(:cancelled), do: "CANCELLED"
  defp status_label(s), do: s |> to_string() |> String.capitalize()

  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Header: date picker + summary stats --%>
      <div class="flex flex-col sm:flex-row sm:items-center gap-4 justify-between">
        <div>
          <h2 class="font-headline text-xl font-bold text-on-surface">Archive Atelier</h2>
          <p class="font-body text-sm text-on-surface-variant mt-0.5">
            Completed and cancelled orders
          </p>
        </div>

        <form phx-change="set_history_date" phx-target={@myself} class="flex items-center gap-2">
          <label class="font-body text-xs uppercase tracking-widest font-bold text-on-surface-variant">
            Date
          </label>
          <input
            type="date"
            name="date"
            value={Date.to_iso8601(@history_date)}
            max={Date.to_iso8601(Date.utc_today())}
            class="rounded-md bg-surface-container-low px-3 py-2 text-sm font-medium text-on-surface border-0 focus:ring-2 focus:ring-primary/30 outline-none"
          />
        </form>
      </div>

      <%!-- Summary cards --%>
      <div class="grid grid-cols-2 gap-8">
        <div class="bg-surface-container-low rounded-md p-6 flex flex-col justify-center">
          <span class="font-body text-xs uppercase tracking-widest font-bold text-on-surface-variant mb-2">
            Orders
          </span>
          <span class="font-headline text-4xl font-black text-on-surface">
            {length(@history_orders)}
          </span>
        </div>
        <div class="bg-secondary-container rounded-md p-6 flex flex-col justify-center">
          <span class="font-body text-xs uppercase tracking-widest font-bold text-on-secondary-container mb-2">
            Revenue
          </span>
          <span class="font-headline text-3xl font-black text-on-secondary-container">
            {if @history_orders == [], do: "$0.00", else: format_money(total_revenue(@history_orders))}
          </span>
        </div>
      </div>

      <%!-- Orders list --%>
      <%= if @history_orders == [] do %>
        <div class="flex flex-col items-center py-24 text-on-surface-variant/20">
          <span class="material-symbols-outlined text-8xl">receipt_long</span>
          <p class="mt-4 text-xl font-black font-headline uppercase tracking-widest opacity-40">
            No history for this date
          </p>
        </div>
      <% else %>
        <div class="space-y-4">
          <div class="hidden md:grid grid-cols-[60px_1fr_1fr_1fr_100px_80px] gap-8 px-4 pb-2 text-[10px] font-bold uppercase tracking-widest text-on-surface-variant/40">
            <span>#</span>
            <span>Customer</span>
            <span>Items</span>
            <span>Time</span>
            <span class="text-right">Total</span>
            <span class="text-right">Status</span>
          </div>

          <%= for order <- @history_orders do %>
            <div class="bg-surface-container-low rounded-md px-4 py-3 grid grid-cols-1 md:grid-cols-[60px_1fr_1fr_1fr_100px_80px] gap-2 md:gap-8 items-center transition-all hover:bg-surface-container-high">
              <div class="bg-primary text-white w-9 h-9 rounded flex items-center justify-center font-headline text-sm font-black italic shrink-0">
                #{order_number(order)}
              </div>

              <div class="min-w-0">
                <p class="font-body text-sm font-bold text-on-surface truncate">
                  {order.customer_name}
                </p>
                <p class="font-body text-[11px] text-on-surface-variant truncate opacity-60">
                  {order.customer_email}
                </p>
              </div>

              <div class="font-body text-xs text-on-surface-variant truncate">
                {order.order_items |> Enum.map(&"#{&1.quantity}x #{&1.item_name}") |> Enum.join(", ")}
              </div>

              <div class="font-body text-xs text-on-surface-variant opacity-60">
                {Calendar.strftime(order.inserted_at, "%I:%M %p")}
              </div>

              <div class="font-body text-sm font-black text-on-surface text-right">
                {format_money(order.total_price)}
              </div>

              <div class="flex justify-end">
                <span class={[
                  "px-2.5 py-1 rounded text-[10px] font-bold uppercase tracking-widest",
                  status_badge_class(order.status)
                ]}>
                  {status_label(order.status)}
                </span>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
