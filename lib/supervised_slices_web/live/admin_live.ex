defmodule SupervisedSlicesWeb.AdminLive do
  use SupervisedSlicesWeb, :live_view

  on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_required}

  alias SupervisedSlices.Cart.Cart
  alias SupervisedSlices.Orders.Order
  alias SupervisedSlices.{OrgPresence, PubSubNotifier}

  alias SupervisedSlicesWeb.AdminLive.OrdersComponent

  def mount(_params, _session, socket) do
    %{org: org, ash_scope: scope} = socket.assigns

    orders = load_active_orders(scope)
    active_carts = load_active_carts(scope)
    visitor_count = org.id |> OrgPresence.list_visitors() |> map_size()

    if connected?(socket) do
      PubSubNotifier.subscribe_to_org_orders(org.id)
      PubSubNotifier.subscribe_to_org_carts(org.id)
      OrgPresence.subscribe(org.id)
    end

    {:ok,
     socket
     |> assign(:visitor_count, visitor_count)
     |> assign(:active_carts, active_carts)
     |> assign(:orders_initial, orders)
     |> assign(:page_title, "Kitchen Command")}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_info({:new_order, order}, socket) do
    loaded = reload_order(order, socket.assigns.ash_scope)
    send_update(OrdersComponent, id: "orders", action: {:insert, loaded})
    {:noreply, assign(socket, :orders_initial, [loaded | socket.assigns.orders_initial])}
  end

  def handle_info({:order_updated, order}, socket) do
    if order.status in [:completed, :cancelled] do
      send_update(OrdersComponent, id: "orders", action: {:delete, order})
      updated = Enum.reject(socket.assigns.orders_initial, &(&1.id == order.id))
      {:noreply, assign(socket, :orders_initial, updated)}
    else
      loaded = reload_order(order, socket.assigns.ash_scope)
      send_update(OrdersComponent, id: "orders", action: {:update, loaded})

      updated =
        Enum.map(socket.assigns.orders_initial, fn o ->
          if o.id == loaded.id, do: loaded, else: o
        end)

      {:noreply, assign(socket, :orders_initial, updated)}
    end
  end

  def handle_info({:cart_updated, cart}, socket) do
    %{ash_scope: scope} = socket.assigns

    full_cart =
      case cart.status do
        :active -> Cart.get!(cart.id, scope: scope, load: [cart_items: [:menu_item]])
        _ -> cart
      end

    {:noreply,
     assign(socket, :active_carts, update_carts(socket.assigns.active_carts, full_cart))}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    count = socket.assigns.org.id |> OrgPresence.list_visitors() |> map_size()
    {:noreply, assign(socket, :visitor_count, count)}
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
end
