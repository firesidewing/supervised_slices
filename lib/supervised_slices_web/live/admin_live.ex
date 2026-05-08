defmodule SupervisedSlicesWeb.AdminLive do
  use SupervisedSlicesWeb, :live_view

  require Ash.Query

  on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_and_subscription_required}

  alias Phoenix.LiveView.AsyncResult
  alias SupervisedSlices.Cart.Cart
  alias SupervisedSlices.Orders.Order
  alias SupervisedSlices.{OrgPresence, PubSubNotifier, Analytics}
  alias SupervisedSlices.Orgs.Organization

  alias SupervisedSlicesWeb.AdminLive.OrdersComponent

  def mount(_params, _session, socket) do
    %{org: org, ash_scope: scope, current_user: current_user} = socket.assigns

    membership =
      SupervisedSlices.Orgs.Membership
      |> Ash.Query.filter(user_id == ^current_user.id and organization_id == ^org.id)
      |> Ash.read_one(authorize?: false)
      |> case do
        {:ok, %SupervisedSlices.Orgs.Membership{} = m} -> m
        _ -> nil
      end

    if is_nil(membership) or membership.role == :customer do
      {:ok, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      visitor_count = org.id |> OrgPresence.list_visitors() |> map_size()

      if connected?(socket) do
        PubSubNotifier.subscribe_to_org_orders(org.id)
        PubSubNotifier.subscribe_to_org_carts(org.id)
        PubSubNotifier.subscribe_to_menu_uploads(org.id)
        PubSubNotifier.subscribe_to_menu(org.id)
        OrgPresence.subscribe(org.id)
        :timer.send_interval(10000, self(), :tick)
      end

      trial_days_remaining =
        if org.subscription_status == :trialing && org.trial_ends_at do
          max(0, DateTime.diff(org.trial_ends_at, DateTime.utc_now(), :day))
        else
          nil
        end

      if trial_days_remaining != nil && trial_days_remaining <= 3 do
        Analytics.capture("trial_ending_soon_shown", org.id, %{
          days_remaining: trial_days_remaining,
          "$groups": %{organization: org.id}
        })
      end

      {:ok,
       socket
       |> assign(:current_membership, membership)
       |> assign(:visitor_count, visitor_count)
       |> assign(:show_phone_order, false)
       |> assign(:page_title, "Kitchen Command")
       |> assign(:trial_days_remaining, trial_days_remaining)
       |> assign_async(:orders_initial, fn ->
         {:ok, %{orders_initial: load_active_orders(scope)}}
       end)
       |> assign_async(:active_carts, fn ->
         {:ok, %{active_carts: load_active_carts(scope)}}
       end)
       |> assign_async(:fire_time_stats, fn ->
         {avg, trend} = load_fire_time_stats(scope, org)
         {:ok, %{fire_time_stats: {avg, trend}}}
       end)}
    end
  end

  def handle_params(_params, _uri, socket) do
    membership = socket.assigns[:current_membership]
    org = socket.assigns.org
    live_action = socket.assigns.live_action

    cond do
      membership && membership.role == :staff &&
          live_action in [:menu, :settings] ->
        {:noreply, Phoenix.LiveView.push_navigate(socket, to: ~p"/kitchen/#{org.slug}")}

      org.plan == :basic && live_action == :insights ->
        {:noreply,
         socket
         |> put_flash(:error, "Order History & Analytics is a Pro feature.")
         |> Phoenix.LiveView.push_navigate(to: ~p"/kitchen/#{org.slug}")}

      true ->
        {:noreply, socket}
    end
  end

  def handle_info({:new_order, order}, socket) do
    loaded = reload_order(order, socket.assigns.ash_scope)
    send_update(OrdersComponent, id: "orders", action: {:insert, loaded})
    current = socket.assigns.orders_initial.result || []
    updated = [loaded | current]

    socket =
      if loaded.status == :pending do
        push_event(socket, "new_order_alert", %{})
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:orders_initial, AsyncResult.ok(updated))
     |> assign(:ticket_count, length(updated))}
  end

  def handle_info({:order_updated, order}, socket) do
    current = socket.assigns.orders_initial.result || []

    if order.status in [:completed, :cancelled] do
      send_update(OrdersComponent, id: "orders", action: {:delete, order})
      updated = Enum.reject(current, &(&1.id == order.id))

      {:noreply,
       socket
       |> assign(:orders_initial, AsyncResult.ok(updated))
       |> assign(:ticket_count, length(updated))}
    else
      loaded = reload_order(order, socket.assigns.ash_scope)
      send_update(OrdersComponent, id: "orders", action: {:update, loaded})
      updated = Enum.map(current, fn o -> if o.id == loaded.id, do: loaded, else: o end)
      {:noreply, assign(socket, :orders_initial, AsyncResult.ok(updated))}
    end
  end

  def handle_info({:cart_updated, cart}, socket) do
    %{ash_scope: scope} = socket.assigns

    full_cart =
      case cart.status do
        :active -> Cart.get!(cart.id, scope: scope, load: [cart_items: [:menu_item]])
        _ -> cart
      end

    current = socket.assigns.active_carts.result || []

    {:noreply, assign(socket, :active_carts, AsyncResult.ok(update_carts(current, full_cart)))}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    count = socket.assigns.org.id |> OrgPresence.list_visitors() |> map_size()
    {:noreply, assign(socket, :visitor_count, count)}
  end

  def handle_info({:phone_order_placed}, socket) do
    {:noreply,
     socket
     |> assign(:show_phone_order, false)
     |> put_flash(:info, "Phone order placed successfully.")}
  end

  def handle_info({:menu_upload_updated, upload}, socket) do
    if upload.status == :completed do
      send_update(SupervisedSlicesWeb.AdminLive.MenuEditorComponent,
        id: "menu-editor",
        current_upload: upload,
        reload_categories: true,
        reload_modifier_groups: true
      )

      {:noreply, put_flash(socket, :info, "Menu import completed successfully!")}
    else
      send_update(SupervisedSlicesWeb.AdminLive.MenuEditorComponent,
        id: "menu-editor",
        current_upload: upload
      )

      socket =
        if upload.status == :failed do
          put_flash(socket, :error, "Menu import failed: #{upload.error_message}")
        else
          socket
        end

      {:noreply, socket}
    end
  end

  def handle_info(:menu_updated, socket) do
    send_update(SupervisedSlicesWeb.AdminLive.MenuEditorComponent,
      id: "menu-editor",
      reload_categories: true,
      reload_modifier_groups: true
    )

    {:noreply, socket}
  end

  def handle_info({:close_phone_order}, socket) do
    {:noreply, assign(socket, :show_phone_order, false)}
  end

  def handle_info(:tick, socket) do
    scope = socket.assigns.ash_scope
    org = socket.assigns.org
    send_update(OrdersComponent, id: "orders", tick: DateTime.utc_now())

    {:noreply,
     assign_async(socket, :fire_time_stats, fn ->
       {avg, trend} = load_fire_time_stats(scope, org)
       {:ok, %{fire_time_stats: {avg, trend}}}
     end)}
  end

  def handle_event("toggle_phone_order", _params, socket) do
    {:noreply, assign(socket, :show_phone_order, !socket.assigns.show_phone_order)}
  end

  def handle_event("tour_completed", _params, socket) do
    membership = socket.assigns.current_membership

    updated =
      membership
      |> Ash.Changeset.for_update(:complete_tour, %{})
      |> Ash.update(authorize?: false)
      |> case do
        {:ok, m} -> m
        _ -> membership
      end

    {:noreply, assign(socket, :current_membership, updated)}
  end

  defp load_active_orders(scope) do
    Order.active!(scope: scope, authorize?: false)
  end

  defp load_active_carts(scope) do
    Cart.active_for_org!(scope: scope)
  end

  defp reload_order(order, scope) do
    Order.get!(order.id, scope: scope, load: :order_items, authorize?: false)
  end

  defp update_carts(carts, cart) do
    case cart.status do
      :active ->
        idx = Enum.find_index(carts, &(&1.id == cart.id))
        if idx, do: List.replace_at(carts, idx, cart), else: [cart | carts]

      _ ->
        Enum.reject(carts, &(&1.id == cart.id))
    end
  end

  defp load_fire_time_stats(scope, org) do
    now = DateTime.utc_now()
    one_hour_ago = DateTime.add(now, -60, :minute)
    two_hours_ago = DateTime.add(now, -120, :minute)

    current_orders =
      Order
      |> Ash.Query.for_read(:read, %{}, scope: scope, authorize?: false)
      |> Ash.Query.filter(status == :completed and updated_at >= ^one_hour_ago)
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&Organization.was_open_at?(org, &1.inserted_at))

    prev_orders =
      Order
      |> Ash.Query.for_read(:read, %{}, scope: scope, authorize?: false)
      |> Ash.Query.filter(
        status == :completed and updated_at >= ^two_hours_ago and updated_at < ^one_hour_ago
      )
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&Organization.was_open_at?(org, &1.inserted_at))

    current_avg = avg_fire_seconds(current_orders)
    prev_avg = avg_fire_seconds(prev_orders)

    trend =
      cond do
        is_nil(current_avg) or is_nil(prev_avg) -> :neutral
        current_avg > prev_avg + 30 -> :up
        current_avg < prev_avg - 30 -> :down
        true -> :neutral
      end

    {current_avg, trend}
  end

  defp avg_fire_seconds([]), do: nil

  defp avg_fire_seconds(orders) do
    total = Enum.sum(Enum.map(orders, &DateTime.diff(&1.updated_at, &1.inserted_at)))
    total / length(orders)
  end

  defp format_fire_time(nil), do: "—"

  defp format_fire_time(seconds) do
    "#{round(seconds / 60)}m"
  end

  defp fire_time_trend_label(:up), do: "↑"
  defp fire_time_trend_label(:down), do: "↓"
  defp fire_time_trend_label(:neutral), do: ""

  defp fire_time_trend_class(:up), do: "text-primary"
  defp fire_time_trend_class(:down), do: "text-secondary"
  defp fire_time_trend_class(:neutral), do: ""
end
