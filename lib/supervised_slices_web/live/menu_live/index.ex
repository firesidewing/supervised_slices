defmodule SupervisedSlicesWeb.MenuLive.Index do
  use SupervisedSlicesWeb, :live_view

  on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_optional}

  alias SupervisedSlices.Accounts.{GuestSession, User}
  alias SupervisedSlices.Cart.{Cart, CartItem}
  alias SupervisedSlices.Menu.Category
  alias SupervisedSlices.Orders.{Order, OrderItem}
  alias SupervisedSlices.OrgPresence
  alias SupervisedSlices.PubSubNotifier

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  def mount(_params, _session, socket) do
    %{org: org, ash_scope: scope} = socket.assigns

    categories =
      Category.active!(
        scope: scope,
        authorize?: false,
        load: [menu_items: [modifier_groups: [:modifiers]]]
      )

    cart = load_cart(scope)
    {cart_items_map, cart_count} = build_cart_state(cart)

    if connected?(socket) do
      OrgPresence.track_visitor(self(), org.id, scope.guest_session_id || "anon", %{})
    end

    {:ok,
     socket
     |> assign(:categories, categories)
     |> assign(:cart, cart)
     |> assign(:cart_items_map, cart_items_map)
     |> assign(:cart_count, cart_count)
     |> assign(:show_basket, false)
     |> assign(:checkout_step, :review)
     |> assign(:page_title, org.name)}
  end

  # ---------------------------------------------------------------------------
  # handle_params
  # ---------------------------------------------------------------------------

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Cart events
  # ---------------------------------------------------------------------------

  def handle_event("toggle_basket", _params, socket) do
    {:noreply, assign(socket, show_basket: !socket.assigns.show_basket, checkout_step: :review)}
  end

  def handle_event("start_checkout", _params, socket) do
    {:noreply, assign(socket, :checkout_step, :confirm)}
  end

  def handle_event("place_order", params, socket) do
    %{ash_scope: scope, cart: cart} = socket.assigns

    dbg(params)

    order =
      Order.place_order!(
        %{
          customer_name: params["customer_name"],
          customer_phone: params["customer_phone"],
          notes: params["notes"],
          total_price: order_total(cart)
        },
        scope: scope
      )

    Enum.each(cart.cart_items, fn item ->
      modifier = order_find_modifier(item)
      price = order_item_price(item, modifier)

      modifiers_snapshot =
        if modifier,
          do: [%{"name" => modifier.name, "price" => Money.to_string!(price)}],
          else: []

      OrderItem.create!(
        %{
          order_id: order.id,
          menu_item_id: item.menu_item_id,
          quantity: item.quantity,
          item_name: item.menu_item.name,
          price_at_time: price,
          modifiers_snapshot: modifiers_snapshot
        },
        scope: scope
      )
    end)

    Cart.checkout!(cart, scope: scope)

    PubSubNotifier.broadcast_new_order(order)

    {:noreply,
     socket
     |> assign(
       cart: nil,
       cart_items_map: %{},
       cart_count: 0,
       show_basket: false,
       checkout_step: :review
     )
     |> put_flash(:info, "Order placed! We'll have it ready soon.")}
  end

  def handle_event(
        "update_quantity",
        %{"item_id" => item_id, "delta" => delta_str} = params,
        socket
      ) do
    modifier_id = Map.get(params, "modifier_id")
    delta = String.to_integer(delta_str)
    key = cart_key(item_id, modifier_id)

    socket =
      case {Map.get(socket.assigns.cart_items_map, key), delta} do
        # Nothing in cart, adding → create cart + cart_item
        {nil, 1} ->
          do_add_item(socket, item_id, modifier_id)

        # Existing item, incrementing
        {%{cart_item_id: cid, quantity: qty}, 1} ->
          do_update_quantity(socket, cid, key, qty + 1)

        # Existing item, at 1 → remove
        {%{cart_item_id: cid, quantity: 1}, -1} ->
          do_remove_item(socket, cid, key)

        # Existing item, decrementing
        {%{cart_item_id: cid, quantity: qty}, -1} ->
          do_update_quantity(socket, cid, key, qty - 1)

        # No-op (e.g. clicking minus on 0)
        _ ->
          socket
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Cart helpers
  # ---------------------------------------------------------------------------

  defp do_add_item(socket, item_id, modifier_id) do
    %{ash_scope: scope, cart: cart} = socket.assigns

    cart = cart || Cart.create!(scope: scope)

    modifier_ids = if modifier_id, do: [modifier_id], else: []

    CartItem.add_to_cart!(
      %{
        cart_id: cart.id,
        menu_item_id: item_id,
        quantity: 1,
        selected_modifier_ids: modifier_ids
      },
      scope: scope
    )

    refresh_cart(socket, cart)
  end

  defp do_update_quantity(socket, cart_item_id, key, new_qty) do
    %{ash_scope: scope, cart_items_map: map} = socket.assigns

    cart_item = CartItem.get!(cart_item_id, scope: scope)
    CartItem.update_quantity!(cart_item, %{quantity: new_qty}, scope: scope)

    new_map = Map.update!(map, key, &%{&1 | quantity: new_qty})
    cart_count = count_cart_items(new_map)
    assign(socket, cart_items_map: new_map, cart_count: cart_count)
  end

  defp do_remove_item(socket, cart_item_id, key) do
    %{ash_scope: scope, cart_items_map: map} = socket.assigns

    CartItem.get!(cart_item_id, scope: scope)
    |> CartItem.destroy!(scope: scope)

    new_map = Map.delete(map, key)
    cart_count = count_cart_items(new_map)
    assign(socket, cart_items_map: new_map, cart_count: cart_count)
  end

  defp refresh_cart(socket, cart) do
    %{ash_scope: scope} = socket.assigns

    loaded_cart =
      Cart.get!(cart.id,
        scope: scope,
        load: [cart_items: [menu_item: [modifier_groups: [:modifiers]]]]
      )

    PubSubNotifier.broadcast_cart_update(loaded_cart)

    {cart_items_map, cart_count} = build_cart_state(loaded_cart)

    assign(socket,
      cart: loaded_cart,
      cart_items_map: cart_items_map,
      cart_count: cart_count
    )
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_cart(scope) do
    cart_load = [cart_items: [menu_item: [modifier_groups: [:modifiers]]]]

    case scope.current_user do
      %User{id: user_id} ->
        case Cart.active_for_user(user_id, scope: scope, load: cart_load) do
          {:ok, cart} -> cart
          _ -> nil
        end

      %GuestSession{id: session_id} ->
        case Cart.active_for_session(session_id, scope: scope, load: cart_load) do
          {:ok, cart} -> cart
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp build_cart_state(nil), do: {%{}, 0}

  defp build_cart_state(cart) do
    items = cart.cart_items || []

    map =
      Enum.reduce(items, %{}, fn item, acc ->
        modifier_id = List.first(item.selected_modifier_ids)
        key = cart_key(to_string(item.menu_item_id), if(modifier_id, do: to_string(modifier_id)))

        Map.put(acc, key, %{
          cart_item_id: item.id,
          quantity: item.quantity
        })
      end)

    {map, count_cart_items(map)}
  end

  defp count_cart_items(map) do
    Enum.reduce(map, 0, fn {_k, %{quantity: q}}, acc -> acc + q end)
  end

  defp cart_key(item_id, nil), do: {item_id, nil}
  defp cart_key(item_id, modifier_id), do: {item_id, modifier_id}

  defp order_find_modifier(cart_item) do
    modifier_id = List.first(cart_item.selected_modifier_ids)

    if modifier_id do
      Enum.find_value(cart_item.menu_item.modifier_groups || [], fn group ->
        Enum.find(group.modifiers || [], &(&1.id == modifier_id))
      end)
    end
  end

  defp order_item_price(cart_item, modifier) do
    base = cart_item.menu_item.price

    if modifier && modifier.price_delta do
      case Money.add(base, modifier.price_delta) do
        {:ok, p} -> p
        _ -> base
      end
    else
      base
    end
  end

  defp order_total(cart) do
    Enum.reduce(cart.cart_items, nil, fn item, acc ->
      modifier = order_find_modifier(item)
      line = Money.mult!(order_item_price(item, modifier), item.quantity)
      if is_nil(acc), do: line, else: elem(Money.add(acc, line), 1)
    end)
  end

  # ---------------------------------------------------------------------------
  # Template helpers (used in HEEx templates)
  # ---------------------------------------------------------------------------

  def item_price(base_price, nil), do: format_money(base_price)

  def item_price(base_price, price_delta) do
    case Money.add(base_price, price_delta) do
      {:ok, total} -> format_money(total)
      _ -> format_money(base_price)
    end
  end

  def format_money(money) do
    Money.to_string!(money)
  rescue
    _ -> "#{money}"
  end

  def get_modifier_qty(cart_items_map, item_id, modifier_id) do
    key = cart_key(to_string(item_id), to_string(modifier_id))
    get_in(cart_items_map, [key, :quantity]) || 0
  end

  def get_item_qty(cart_items_map, item_id) do
    key = cart_key(to_string(item_id), nil)
    get_in(cart_items_map, [key, :quantity]) || 0
  end
end
