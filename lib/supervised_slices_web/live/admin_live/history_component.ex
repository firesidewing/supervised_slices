defmodule SupervisedSlicesWeb.AdminLive.HistoryComponent do
  use SupervisedSlicesWeb, :live_component

  require Ash.Query

  alias SupervisedSlices.Orders.Order

  def update(assigns, socket) do
    socket =
      socket
      |> assign(:ash_scope, assigns.ash_scope)
      |> assign_new(:history_date, fn -> Date.utc_today() end)

    socket =
      if Map.has_key?(socket.assigns, :history_orders) do
        socket
      else
        scope = assigns.ash_scope
        date = socket.assigns.history_date

        assign_async(socket, :history_orders, fn ->
          {:ok, %{history_orders: load_history(scope, date)}}
        end)
      end

    {:ok, socket}
  end

  def handle_event("set_history_date", %{"date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        scope = socket.assigns.ash_scope

        {:noreply,
         socket
         |> assign(:history_date, date)
         |> cancel_async(:history_orders)
         |> assign_async(:history_orders, fn ->
           {:ok, %{history_orders: load_history(scope, date)}}
         end)}

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
    |> Enum.filter(&(&1.status == :completed))
    |> Enum.reduce(Money.new!(:CAD, "0"), fn order, acc ->
      Money.add!(acc, order.total_price)
    end)
  end

  defp total_completed_items_qty(orders) do
    orders
    |> Enum.filter(&(&1.status == :completed))
    |> Enum.flat_map(&(&1.order_items || []))
    |> Enum.map(& &1.quantity)
    |> Enum.sum()
  end

  defp top_items(orders) do
    orders
    |> Enum.filter(&(&1.status == :completed))
    |> Enum.flat_map(&(&1.order_items || []))
    |> Enum.group_by(& &1.item_name)
    |> Enum.map(fn {name, items} ->
      %{name: name, quantity: Enum.sum(Enum.map(items, & &1.quantity))}
    end)
    |> Enum.sort_by(& &1.quantity, :desc)
    |> Enum.take(5)
  end

  defp orders_by_hour(orders) do
    # Group by hour (0..23)
    orders
    |> Enum.group_by(fn order ->
      order.inserted_at.hour
    end)
    |> Enum.map(fn {hour, orders} -> {hour, length(orders)} end)
    |> Enum.into(%{})
  end

  defp avg_completion_time(orders) do
    completed_orders = Enum.filter(orders, &(&1.status == :completed))

    if Enum.empty?(completed_orders) do
      nil
    else
      total_seconds =
        completed_orders
        |> Enum.map(fn order ->
          DateTime.diff(order.updated_at, order.inserted_at)
        end)
        |> Enum.sum()

      trunc(total_seconds / length(completed_orders) / 60)
    end
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
          <span
            :if={@history_orders.loading}
            class="ml-1 text-on-surface-variant/40"
            title="Loading..."
          >
            <.icon name="hero-arrow-path" class="size-4 animate-spin" />
          </span>
        </form>
      </div>

      <%!-- Summary cards --%>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-8">
        <div class="bg-surface-container-low rounded-md p-6 flex flex-col justify-center">
          <span class="font-body text-xs uppercase tracking-widest font-bold text-on-surface-variant mb-2">
            Orders
          </span>
          <span class="font-headline text-4xl font-black text-on-surface">
            <%= if @history_orders.loading do %>
              <span class="inline-block h-10 w-12 bg-surface-container animate-pulse rounded" />
            <% else %>
              {length(@history_orders.result || [])}
            <% end %>
          </span>
        </div>
        <div class="bg-secondary-container rounded-md p-6 flex flex-col justify-center">
          <span class="font-body text-xs uppercase tracking-widest font-bold text-on-secondary-container mb-2">
            Revenue
          </span>
          <span class="font-headline text-3xl font-black text-on-secondary-container">
            <%= if @history_orders.loading do %>
              <span class="inline-block h-9 w-24 bg-secondary-container-high animate-pulse rounded" />
            <% else %>
              {if Enum.empty?(@history_orders.result || []),
                do: "$0.00",
                else: format_money(total_revenue(@history_orders.result))}
            <% end %>
          </span>
        </div>
        <div class="bg-surface-container-low rounded-md p-6 flex flex-col justify-center">
          <span class="font-body text-xs uppercase tracking-widest font-bold text-on-surface-variant mb-2">
            Avg. Prep Time
          </span>
          <span class="font-headline text-3xl font-black text-on-surface">
            <%= if @history_orders.loading do %>
              <span class="inline-block h-9 w-16 bg-surface-container animate-pulse rounded" />
            <% else %>
              {avg_completion_time(@history_orders.result || []) || "-"}
              <span class="text-xs font-body font-normal opacity-60 ml-1">mins</span>
            <% end %>
          </span>
        </div>
        <div class="bg-surface-container-low rounded-md p-6 flex flex-col justify-center">
          <span class="font-body text-xs uppercase tracking-widest font-bold text-on-surface-variant mb-2">
            Top Selling
          </span>
          <span class="font-headline text-xl font-bold text-on-surface truncate">
            <%= if @history_orders.loading do %>
              <span class="inline-block h-7 w-32 bg-surface-container animate-pulse rounded" />
            <% else %>
              {case top_items(@history_orders.result || []) do
                [%{name: name} | _] -> name
                _ -> "-"
              end}
            <% end %>
          </span>
        </div>
      </div>

      <%!-- Insights Grid --%>
      <%= if !@history_orders.loading && !Enum.empty?(@history_orders.result || []) do %>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
          <%!-- Order Volume Chart --%>
          <div class="bg-surface-container-low rounded-md p-8">
            <h3 class="font-headline text-sm font-bold text-on-surface uppercase tracking-widest mb-8">
              Order Volume Distribution
            </h3>
            <div class="flex items-end gap-1 h-32">
              <% volumes = orders_by_hour(@history_orders.result) %>
              <% max_volume = volumes |> Map.values() |> Enum.max(fn -> 1 end) %>
              <%= for hour <- 0..23 do %>
                <% vol = Map.get(volumes, hour, 0) %>
                <% height = if max_volume > 0, do: trunc(vol / max_volume * 100), else: 0 %>
                <div class="group relative flex-1">
                  <div
                    class="w-full bg-primary/20 rounded-t-sm transition-all hover:bg-primary"
                    style={"height: #{max(height, 2)}%;"}
                  >
                  </div>
                  <div class="absolute -bottom-6 left-1/2 -translate-x-1/2 hidden group-hover:block whitespace-nowrap bg-on-surface text-surface text-[10px] px-2 py-1 rounded-sm z-10">
                    {hour}:00 — {vol} orders
                  </div>
                </div>
              <% end %>
            </div>
            <div class="flex justify-between mt-4 text-[9px] font-bold uppercase tracking-[0.2em] text-on-surface-variant/40">
              <span>Midnight</span>
              <span>Noon</span>
              <span>11 PM</span>
            </div>
          </div>

          <%!-- Top Items List --%>
          <div class="bg-surface-container-low rounded-md p-8">
            <h3 class="font-headline text-sm font-bold text-on-surface uppercase tracking-widest mb-6">
              Menu Performance
            </h3>
            <div class="space-y-4">
              <%= for %{name: name, quantity: qty} <- top_items(@history_orders.result) do %>
                <div class="flex items-center justify-between">
                  <span class="font-body text-sm font-bold text-on-surface">{name}</span>
                  <div class="flex items-center gap-4 flex-1 max-w-[200px] ml-4">
                    <% total_qty = total_completed_items_qty(@history_orders.result) %>
                    <% percent = if total_qty > 0, do: trunc(qty / total_qty * 100), else: 0 %>
                    <div class="h-1.5 flex-1 bg-surface-container rounded-full overflow-hidden">
                      <div class="h-full bg-secondary" style={"width: #{percent}%"}></div>
                    </div>
                    <span class="font-body text-xs font-bold text-on-surface-variant w-8 text-right">
                      {qty}
                    </span>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Orders list header --%>
      <div class="pt-4">
        <h3 class="font-headline text-lg font-bold text-on-surface border-b-0">
          Transaction Journal
        </h3>
      </div>

      <%!-- Orders list --%>
      <%= if @history_orders.loading do %>
        <div class="flex flex-col items-center py-24 text-on-surface-variant/20">
          <.icon name="hero-arrow-path" class="size-10 animate-spin opacity-30" />
        </div>
      <% else %>
        <%= if Enum.empty?(@history_orders.result || []) do %>
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

            <%= for order <- @history_orders.result do %>
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
                  {order.order_items
                  |> Enum.map(&"#{&1.quantity}x #{&1.item_name}")
                  |> Enum.join(", ")}
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
      <% end %>
    </div>
    """
  end
end
