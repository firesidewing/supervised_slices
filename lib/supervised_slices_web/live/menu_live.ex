defmodule SupervisedSlicesWeb.MenuLive do
  use SupervisedSlicesWeb, :live_view

  on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_optional}

  alias SupervisedSlices.Accounts.{GuestSession, User}
  alias SupervisedSlices.Cart.{Cart, CartItem}
  alias SupervisedSlices.Menu.{Category, MenuItem}
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
        load: [menu_items: [modifier_groups: [:modifiers], sizes: []]]
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
     |> assign(:selected_item, nil)
     |> assign(:page_title, org.name)}
  end

  # ---------------------------------------------------------------------------
  # handle_params
  # ---------------------------------------------------------------------------

  def handle_params(%{"id" => id}, _uri, socket) do
    item =
      MenuItem.get!(id,
        scope: socket.assigns.ash_scope,
        authorize?: false,
        load: [modifier_groups: [:modifiers], sizes: []]
      )

    {:noreply,
     socket
     |> assign(:selected_item, item)
     |> assign(:page_title, item.name)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:selected_item, nil)
     |> assign(:page_title, socket.assigns.org.name)}
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
    %{ash_scope: scope, cart: cart, org: org} = socket.assigns

    subtotal = order_subtotal(cart)
    tax_amount = order_tax_amount(subtotal, org.tax_rate)
    {:ok, total_price} = Money.add(subtotal, tax_amount)

    order =
      Order.place_order!(
        %{
          customer_name: params["customer_name"],
          customer_phone: params["customer_phone"],
          notes: params["notes"],
          total_price: total_price,
          tax_amount: tax_amount
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

      size_snapshot =
        case item.selected_size do
          %{name: name, price: p} -> %{"name" => name, "price" => Money.to_string!(p)}
          _ -> nil
        end

      OrderItem.create!(
        %{
          order_id: order.id,
          menu_item_id: item.menu_item_id,
          quantity: item.quantity,
          item_name: item.menu_item.name,
          price_at_time: price,
          modifiers_snapshot: modifiers_snapshot,
          size_snapshot: size_snapshot
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
     |> push_navigate(to: ~p"/orders/#{org.slug}/#{order.id}")}
  end

  def handle_event(
        "update_quantity",
        %{"item_id" => item_id, "delta" => delta_str} = params,
        socket
      ) do
    modifier_id = Map.get(params, "modifier_id")
    size_id = Map.get(params, "size_id")
    delta = String.to_integer(delta_str)
    key = cart_key(item_id, size_id, modifier_id)

    socket =
      case {Map.get(socket.assigns.cart_items_map, key), delta} do
        {nil, 1} ->
          do_add_item(socket, item_id, size_id, modifier_id)

        {%{cart_item_id: cid, quantity: qty}, 1} ->
          do_update_quantity(socket, cid, key, qty + 1)

        {%{cart_item_id: cid, quantity: 1}, -1} ->
          do_remove_item(socket, cid, key)

        {%{cart_item_id: cid, quantity: qty}, -1} ->
          do_update_quantity(socket, cid, key, qty - 1)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Cart helpers
  # ---------------------------------------------------------------------------

  defp do_add_item(socket, item_id, size_id, modifier_id) do
    %{ash_scope: scope, cart: cart} = socket.assigns

    cart = cart || Cart.create!(scope: scope)

    modifier_ids = if modifier_id, do: [modifier_id], else: []

    CartItem.add_to_cart!(
      %{
        cart_id: cart.id,
        menu_item_id: item_id,
        quantity: 1,
        selected_modifier_ids: modifier_ids,
        selected_size_id: size_id
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
        load: [cart_items: [:selected_size, menu_item: [modifier_groups: [:modifiers]]]]
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
    cart_load = [cart_items: [:selected_size, menu_item: [modifier_groups: [:modifiers]]]]

    case scope.current_user do
      %User{id: user_id} ->
        case Cart.active_for_user(user_id, scope: scope, load: cart_load, authorize?: false) do
          {:ok, cart} -> cart
          _ -> nil
        end

      %GuestSession{id: session_id} ->
        case Cart.active_for_session(session_id, scope: scope, load: cart_load, authorize?: false) do
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
        size_id = item.selected_size_id

        key =
          cart_key(
            to_string(item.menu_item_id),
            if(size_id, do: to_string(size_id)),
            if(modifier_id, do: to_string(modifier_id))
          )

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

  defp cart_key(item_id, size_id, modifier_id), do: {item_id, size_id, modifier_id}

  defp order_find_modifier(cart_item) do
    modifier_id = List.first(cart_item.selected_modifier_ids)

    if modifier_id do
      Enum.find_value(cart_item.menu_item.modifier_groups || [], fn group ->
        Enum.find(group.modifiers || [], &(&1.id == modifier_id))
      end)
    end
  end

  defp order_item_price(cart_item, modifier) do
    base =
      case cart_item.selected_size do
        %{price: size_price} -> size_price
        _ -> cart_item.menu_item.price
      end

    if modifier && modifier.price_delta do
      case Money.add(base, modifier.price_delta) do
        {:ok, p} -> p
        _ -> base
      end
    else
      base
    end
  end

  defp order_subtotal(cart) do
    Enum.reduce(cart.cart_items, nil, fn item, acc ->
      modifier = order_find_modifier(item)
      line = Money.mult!(order_item_price(item, modifier), item.quantity)
      if is_nil(acc), do: line, else: elem(Money.add(acc, line), 1)
    end)
  end

  defp order_tax_amount(subtotal, tax_rate) do
    if Decimal.compare(tax_rate, Decimal.new("0")) == :gt do
      Money.mult!(subtotal, tax_rate)
    else
      Money.new!(0, subtotal.currency)
    end
  end

  # ---------------------------------------------------------------------------
  # Template
  # ---------------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <header class="fixed top-0 w-full z-50 bg-background/80 backdrop-blur-xl flex items-center gap-4 px-4 py-4">
      <.link
        :if={@live_action == :show}
        navigate={~p"/menu/#{@org.slug}"}
        class="flex items-center justify-center w-10 h-10 rounded-full hover:bg-surface-container transition-colors text-on-surface-variant active:scale-95"
        aria-label="Back to menu"
      >
        <span class="material-symbols-outlined">arrow_back</span>
      </.link>
      <h1 class="font-headline text-xl font-bold tracking-tight text-primary-container">
        {@org.name}
      </h1>
      <div :if={@live_action == :index} class="ml-auto flex items-center gap-3">
        <button
          phx-click="toggle_basket"
          class="text-on-surface-variant hover:scale-105 transition-transform active:scale-95 relative"
        >
          <span class="material-symbols-outlined">shopping_bag</span>
          <span
            :if={@cart_count > 0}
            class="absolute -top-1 -right-1 bg-primary text-white text-[10px] font-black rounded-full w-4 h-4 flex items-center justify-center leading-none"
          >
            {@cart_count}
          </span>
        </button>
      </div>
    </header>

    <.live_component
      :if={@live_action == :index}
      module={SupervisedSlicesWeb.MenuLive.MenuComponent}
      id="menu"
      categories={@categories}
      cart_items_map={@cart_items_map}
      org={@org}
    />

    <.live_component
      :if={@live_action == :show && @selected_item != nil}
      module={SupervisedSlicesWeb.MenuLive.ItemComponent}
      id="item"
      selected_item={@selected_item}
      cart_items_map={@cart_items_map}
      org={@org}
    />

    <.menu_nav cart_count={@cart_count} org={@org} />

    <.basket_drawer cart={@cart} show={@show_basket} checkout_step={@checkout_step} tax_rate={@org.tax_rate} />

    <div class="fixed top-[15%] right-[-20px] opacity-10 pointer-events-none transform rotate-45 select-none hidden lg:block text-on-surface">
      <span class="material-symbols-outlined" style="font-size: 120px;">potted_plant</span>
    </div>
    <div class="fixed bottom-[12%] left-[-20px] opacity-10 pointer-events-none transform -rotate-12 select-none hidden lg:block text-on-surface">
      <span class="material-symbols-outlined" style="font-size: 150px;">cooking</span>
    </div>
    """
  end

  defp menu_nav(assigns) do
    ~H"""
    <nav class="fixed bottom-6 left-0 right-0 flex justify-center items-center px-4 z-50 pointer-events-none">
      <div class="pointer-events-auto w-[90%] max-w-lg bg-gradient-to-r from-primary to-primary-container rounded-full flex justify-around items-center px-4 py-2 shadow-[0px_12px_32px_rgba(185,0,39,0.25)]">
        <.link
          navigate={~p"/menu/#{@org.slug}"}
          class="flex items-center gap-2 bg-white/20 rounded-full px-5 py-2.5 text-white font-bold hover:scale-[1.02] transition-all active:scale-95"
        >
          <span class="material-symbols-outlined">restaurant_menu</span>
          <span class="font-body text-[10px] uppercase tracking-widest">
            Explore Menu
          </span>
        </.link>
        <button
          phx-click="toggle_basket"
          class="flex items-center gap-1.5 text-white/80 px-5 py-2.5 hover:scale-[1.02] transition-all active:scale-95"
        >
          <span class="material-symbols-outlined">shopping_cart_checkout</span>
          <span class="font-body text-[10px] uppercase tracking-widest">
            View Basket
          </span>
          <span
            :if={@cart_count > 0}
            class="ml-1 bg-white text-primary text-[10px] font-black rounded-full w-5 h-5 flex items-center justify-center"
          >
            {@cart_count}
          </span>
        </button>
      </div>
    </nav>
    """
  end
end
