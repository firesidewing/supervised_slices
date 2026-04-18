defmodule SupervisedSlicesWeb.AdminLive.InsightsComponent do
  use SupervisedSlicesWeb, :live_component

  require Ash.Query

  alias SupervisedSlices.Orders.Order
  alias SupervisedSlices.Orgs.Organization

  def update(assigns, socket) do
    socket =
      socket
      |> assign(:ash_scope, assigns.ash_scope)
      |> assign(:org, assigns.org)
      |> assign_new(:tab, fn -> :daily end)
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

    socket =
      if Map.has_key?(socket.assigns, :metrics) do
        socket
      else
        scope = assigns.ash_scope

        assign_async(socket, :metrics, fn -> fetch_metrics(scope, assigns.org) end)
      end

    {:ok, socket}
  end

  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, String.to_existing_atom(tab))}
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

  # ─── Data loading ───────────────────────────────────────────────────────────

  defp load_history(scope, date) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.add(start_dt, 86400, :second)

    Order
    |> Ash.Query.for_read(:completed, %{}, scope: scope, authorize?: false)
    |> Ash.Query.filter(inserted_at >= ^start_dt and inserted_at < ^end_dt)
    |> Ash.read!(authorize?: false)
  end

  defp fetch_metrics(scope, org) do
    now = DateTime.utc_now()
    month_start = %{now | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    thirty_days_ago = DateTime.add(now, -30, :day)

    orders =
      Order
      |> Ash.Query.for_read(:read, %{}, scope: scope, authorize?: false)
      |> Ash.Query.filter(inserted_at >= ^thirty_days_ago and status != :cancelled)
      |> Ash.read!(authorize?: false, load: [:order_items])
      |> Enum.filter(&Organization.was_open_at?(org, &1.inserted_at))

    orders_this_month =
      Enum.filter(orders, &(DateTime.compare(&1.inserted_at, month_start) != :lt))

    orders_total = length(orders_this_month)

    orders_by_day =
      orders
      |> Enum.group_by(&DateTime.to_date(&1.inserted_at))
      |> Enum.map(fn {date, os} -> {date, length(os)} end)
      |> Enum.sort_by(&elem(&1, 0), Date)

    top_items =
      orders_this_month
      |> Enum.flat_map(& &1.order_items)
      |> Enum.group_by(& &1.item_name)
      |> Enum.map(fn {name, items} -> {name, length(items)} end)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.take(10)

    {:ok,
     %{
       metrics: %{
         orders_total: orders_total,
         orders_by_day: orders_by_day,
         top_items: top_items
       }
     }}
  end

  # ─── Helpers ────────────────────────────────────────────────────────────────

  defp format_money(nil), do: "-"
  defp format_money(%Money{} = m), do: Money.to_string!(m)

  defp order_number(order), do: order.id |> String.slice(-4..-1)

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
    orders
    |> Enum.group_by(& &1.inserted_at.hour)
    |> Enum.map(fn {hour, orders} -> {hour, length(orders)} end)
    |> Enum.into(%{})
  end

  defp avg_completion_time(orders) do
    completed = Enum.filter(orders, &(&1.status == :completed))

    if Enum.empty?(completed) do
      nil
    else
      total_seconds =
        completed
        |> Enum.map(fn o -> DateTime.diff(o.updated_at, o.inserted_at) end)
        |> Enum.sum()

      trunc(total_seconds / length(completed) / 60)
    end
  end

  defp status_badge_class(:completed), do: "bg-secondary-container text-on-secondary-container"
  defp status_badge_class(:cancelled), do: "bg-surface-container-highest text-on-surface-variant"
  defp status_badge_class(_), do: "bg-surface-container text-on-surface-variant"

  defp status_label(:completed), do: "DONE"
  defp status_label(:cancelled), do: "CANCELLED"
  defp status_label(s), do: s |> to_string() |> String.capitalize()

  # ─── Render ─────────────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div class="flex border-b border-on-surface/10">
        <button
          phx-click="set_tab"
          phx-value-tab="daily"
          phx-target={@myself}
          class={[
            "px-6 py-3 font-headline font-bold text-sm uppercase tracking-widest border-b-2 -mb-px transition-colors",
            if(@tab == :daily,
              do: "border-primary text-primary",
              else: "border-transparent text-on-surface-variant/60 hover:text-on-surface"
            )
          ]}
        >
          Daily
        </button>
        <button
          phx-click="set_tab"
          phx-value-tab="trends"
          phx-target={@myself}
          class={[
            "px-6 py-3 font-headline font-bold text-sm uppercase tracking-widest border-b-2 -mb-px transition-colors",
            if(@tab == :trends,
              do: "border-primary text-primary",
              else: "border-transparent text-on-surface-variant/60 hover:text-on-surface"
            )
          ]}
        >
          Trends
        </button>
      </div>

      <%= if @tab == :daily do %>
        <%!-- Date picker --%>
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

        <%!-- Charts --%>
        <%= if !@history_orders.loading && !Enum.empty?(@history_orders.result || []) do %>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
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

        <%!-- Transaction journal --%>
        <div class="pt-4">
          <h3 class="font-headline text-lg font-bold text-on-surface">Transaction Journal</h3>
        </div>

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
      <% end %>

      <%= if @tab == :trends do %>
        <.async_result :let={metrics} assign={@metrics}>
          <:loading>
            <div class="flex items-center justify-center py-24">
              <span class="loading loading-spinner loading-md text-primary"></span>
            </div>
          </:loading>

          <:failed>
            <div class="py-16 text-center text-on-surface-variant font-body text-sm">
              Could not load analytics. Please try again later.
            </div>
          </:failed>

          <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-10">
            <div class="bg-surface-container-low rounded-md p-6">
              <p class="font-body text-xs uppercase tracking-widest text-on-surface-variant mb-1">
                Orders this month
              </p>
              <p class="font-headline text-4xl font-bold text-on-surface">{metrics.orders_total}</p>
            </div>
            <div class="bg-surface-container-low rounded-md p-6">
              <p class="font-body text-xs uppercase tracking-widest text-on-surface-variant mb-1">
                Avg orders / day
              </p>
              <p class="font-headline text-4xl font-bold text-on-surface">
                {if length(metrics.orders_by_day) > 0,
                  do: Float.round(metrics.orders_total / length(metrics.orders_by_day), 1),
                  else: 0}
              </p>
            </div>
            <div class="bg-surface-container-low rounded-md p-6">
              <p class="font-body text-xs uppercase tracking-widest text-on-surface-variant mb-1">
                Active days
              </p>
              <p class="font-headline text-4xl font-bold text-on-surface">
                {length(metrics.orders_by_day)}
              </p>
            </div>
          </div>

          <div
            :if={length(metrics.orders_by_day) > 0}
            class="bg-surface-container-low rounded-md p-6 mb-10"
          >
            <p class="font-body text-xs uppercase tracking-widest text-on-surface-variant mb-6">
              Orders per day (last 30 days)
            </p>
            <% max_orders = metrics.orders_by_day |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end) %>
            <div class="flex items-end gap-1 h-32">
              <div
                :for={{date, count} <- metrics.orders_by_day}
                class="flex-1 flex flex-col items-center group relative"
              >
                <div
                  class="w-full bg-primary rounded-t-sm hover:bg-primary-container cursor-default transition-colors"
                  style={"height: #{max(round(count / max_orders * 100), 4)}%"}
                  title={"#{date}: #{count} order#{if count != 1, do: "s"}"}
                >
                </div>
              </div>
            </div>
            <div class="flex justify-between mt-2">
              <span class="font-body text-xs text-on-surface-variant">
                {metrics.orders_by_day |> List.first() |> then(fn {d, _} -> d end)}
              </span>
              <span class="font-body text-xs text-on-surface-variant">
                {metrics.orders_by_day |> List.last() |> then(fn {d, _} -> d end)}
              </span>
            </div>
          </div>

          <div
            :if={length(metrics.orders_by_day) == 0}
            class="bg-surface-container-low rounded-md p-6 mb-10"
          >
            <p class="font-body text-xs uppercase tracking-widest text-on-surface-variant mb-2">
              Orders per day (last 30 days)
            </p>
            <p class="font-body text-sm text-on-surface-variant">No orders in this period yet.</p>
          </div>

          <div class="bg-surface-container-low rounded-md p-6">
            <p class="font-body text-xs uppercase tracking-widest text-on-surface-variant mb-6">
              Most ordered items this month
            </p>
            <div :if={length(metrics.top_items) > 0} class="space-y-4">
              <% item_max = metrics.top_items |> Enum.map(&elem(&1, 1)) |> List.first() |> max(1) %>
              <div
                :for={{{name, count}, idx} <- Enum.with_index(metrics.top_items)}
                class="flex items-center gap-4"
              >
                <span class="font-body text-xs text-on-surface-variant w-4 text-right shrink-0">
                  {idx + 1}
                </span>
                <div class="flex-1">
                  <div class="flex justify-between mb-1">
                    <span class="font-body text-sm text-on-surface">{name}</span>
                    <span class="font-body text-sm text-on-surface-variant">{count}</span>
                  </div>
                  <div class="h-1.5 bg-surface-container rounded-full overflow-hidden">
                    <div
                      class="h-full bg-primary rounded-full"
                      style={"width: #{round(count / item_max * 100)}%"}
                    >
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <p
              :if={length(metrics.top_items) == 0}
              class="font-body text-sm text-on-surface-variant"
            >
              No orders this month yet.
            </p>
          </div>
        </.async_result>
      <% end %>
    </div>
    """
  end
end
