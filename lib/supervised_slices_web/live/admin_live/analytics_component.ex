defmodule SupervisedSlicesWeb.AdminLive.AnalyticsComponent do
  use SupervisedSlicesWeb, :live_component

  import Ecto.Query

  alias SupervisedSlices.Repo

  def update(%{org: org} = assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns[:metrics] do
      {:ok, socket}
    else
      {:ok, assign_async(socket, :metrics, fn -> fetch_metrics(org.id) end)}
    end
  end

  defp fetch_metrics(org_id) do
    now = DateTime.utc_now()
    month_start = %{now | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    thirty_days_ago = DateTime.add(now, -30, :day)

    orders_total =
      Repo.one(
        from o in "orders",
          where:
            o.organization_id == ^org_id and
              o.inserted_at >= ^month_start and
              o.status != "cancelled",
          select: count()
      )

    orders_by_day =
      Repo.all(
        from o in "orders",
          where:
            o.organization_id == ^org_id and
              o.inserted_at >= ^thirty_days_ago and
              o.status != "cancelled",
          group_by: fragment("date(? AT TIME ZONE 'UTC')", o.inserted_at),
          order_by: fragment("date(? AT TIME ZONE 'UTC')", o.inserted_at),
          select: {fragment("date(? AT TIME ZONE 'UTC')", o.inserted_at), count()}
      )

    top_items =
      Repo.all(
        from oi in "order_items",
          join: o in "orders",
          on: o.id == oi.order_id,
          where:
            oi.organization_id == ^org_id and
              o.inserted_at >= ^month_start and
              o.status != "cancelled",
          group_by: oi.item_name,
          order_by: [desc: count()],
          limit: 10,
          select: {oi.item_name, count()}
      )

    {:ok,
     %{
       metrics: %{
         orders_total: orders_total || 0,
         orders_by_day: orders_by_day,
         top_items: top_items
       }
     }}
  end

  def render(assigns) do
    ~H"""
    <div>
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

        <%!-- Stats row --%>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-10">
          <div class="bg-surface-container-low rounded-2xl p-6">
            <p class="font-body text-xs uppercase tracking-widest text-on-surface-variant mb-1">
              Orders this month
            </p>
            <p class="font-headline text-4xl font-bold text-on-surface">{metrics.orders_total}</p>
          </div>
          <div class="bg-surface-container-low rounded-2xl p-6">
            <p class="font-body text-xs uppercase tracking-widest text-on-surface-variant mb-1">
              Avg orders / day
            </p>
            <p class="font-headline text-4xl font-bold text-on-surface">
              {if length(metrics.orders_by_day) > 0,
                do: Float.round(metrics.orders_total / length(metrics.orders_by_day), 1),
                else: 0}
            </p>
          </div>
          <div class="bg-surface-container-low rounded-2xl p-6">
            <p class="font-body text-xs uppercase tracking-widest text-on-surface-variant mb-1">
              Active days
            </p>
            <p class="font-headline text-4xl font-bold text-on-surface">
              {length(metrics.orders_by_day)}
            </p>
          </div>
        </div>

        <%!-- Orders by day chart --%>
        <div
          :if={length(metrics.orders_by_day) > 0}
          class="bg-surface-container-low rounded-2xl p-6 mb-10"
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
          class="bg-surface-container-low rounded-2xl p-6 mb-10"
        >
          <p class="font-body text-xs uppercase tracking-widest text-on-surface-variant mb-2">
            Orders per day (last 30 days)
          </p>
          <p class="font-body text-sm text-on-surface-variant">No orders in this period yet.</p>
        </div>

        <%!-- Top items --%>
        <div class="bg-surface-container-low rounded-2xl p-6">
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
          <p :if={length(metrics.top_items) == 0} class="font-body text-sm text-on-surface-variant">
            No orders this month yet.
          </p>
        </div>
      </.async_result>
    </div>
    """
  end
end
