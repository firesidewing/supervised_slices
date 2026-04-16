defmodule SupervisedSlicesWeb.MenuLive do
  use SupervisedSlicesWeb, :live_view

  on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_optional}

  alias Phoenix.LiveView.AsyncResult
  alias SupervisedSlices.Accounts.{GuestSession, User}
  alias SupervisedSlices.Cart.{Cart, CartItem}
  alias SupervisedSlices.Menu.{Category, MenuItem}
  alias SupervisedSlices.Orders.{Order, OrderItem, Emails}
  alias SupervisedSlices.Orgs.GeofenceChecker
  alias SupervisedSlices.OrgPresence
  alias SupervisedSlices.PubSubNotifier

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  def mount(_params, _session, socket) do
    %{org: org, ash_scope: scope} = socket.assigns

    cart = load_cart(scope)
    {cart_items_map, cart_count} = build_cart_state(cart)

    if connected?(socket) do
      OrgPresence.track_visitor(self(), org.id, scope.guest_session_id || "anon", %{})
    end

    {:ok,
     socket
     |> assign_async(:categories, fn ->
       categories =
         Category.active!(
           scope: scope,
           authorize?: false,
           load: [menu_items: [modifier_groups: [:modifiers], sizes: []]]
         )

       {:ok, %{categories: categories}}
     end)
     |> assign(:selected_item, AsyncResult.ok(nil))
     |> assign(:selected_item_id, nil)
     |> assign(:selected_item_has_image, false)
     |> assign(:cart, cart)
     |> assign(:cart_items_map, cart_items_map)
     |> assign(:cart_count, cart_count)
     |> assign(:show_basket, false)
     |> assign(:checkout_step, :review)
     |> assign(:upsells_dismissed, false)
     |> assign(:store_open, SupervisedSlices.Orgs.Organization.open_now?(org))
     |> assign(:page_title, org.name)}
  end

  # ---------------------------------------------------------------------------
  # handle_params
  # ---------------------------------------------------------------------------

  def handle_params(%{"id" => id}, _uri, socket) do
    scope = socket.assigns.ash_scope
    quick_item = find_item_in_categories(socket.assigns.categories, id)
    org = socket.assigns.org
    item_name = quick_item && quick_item.name

    {:noreply,
     socket
     |> cancel_async(:selected_item)
     |> assign(:selected_item_id, id)
     |> assign(:selected_item_has_image, quick_item != nil && !is_nil(quick_item.image_url))
     |> assign(:quick_item, quick_item)
     |> push_event("ph:capture", %{event: "item_viewed", props: %{item_id: id, item_name: item_name, org_id: org.id}})
     |> assign_async(:selected_item, fn ->
       item =
         MenuItem.get!(id,
           scope: scope,
           authorize?: false,
           load: [modifier_groups: [:modifiers], sizes: []]
         )

       {:ok, %{selected_item: item, selected_item_has_image: !is_nil(item.image_url)}}
     end)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> cancel_async(:selected_item)
     |> assign(:selected_item, AsyncResult.ok(nil))
     |> assign(:selected_item_id, nil)
     |> assign(:quick_item, nil)
     |> assign(:page_title, socket.assigns.org.name)}
  end

  defp find_item_in_categories(%{ok?: true, result: categories}, id) do
    categories
    |> Enum.flat_map(& &1.menu_items)
    |> Enum.find(&(to_string(&1.id) == id))
  end

  defp find_item_in_categories(_, _), do: nil

  def handle_info({:cart_refreshed, loaded_cart}, socket) do
    {cart_items_map, cart_count} = build_cart_state(loaded_cart)

    {:noreply,
     assign(socket, cart: loaded_cart, cart_items_map: cart_items_map, cart_count: cart_count)}
  end

  def handle_event("toggle_basket", _params, socket) do
    opening = !socket.assigns.show_basket

    socket =
      if opening do
        push_event(socket, "ph:capture", %{event: "basket_opened", props: %{item_count: socket.assigns.cart_count, org_id: socket.assigns.org.id}})
      else
        socket
      end

    {:noreply, assign(socket, show_basket: opening, checkout_step: :review)}
  end

  def handle_event("dismiss_upsells", _params, socket) do
    {:noreply, assign(socket, :upsells_dismissed, true)}
  end

  def handle_event("update_delivery_type", %{"delivery_type" => type}, socket) do
    %{ash_scope: scope, cart: cart, org: org} = socket.assigns
    type = String.to_existing_atom(type)

    if cart do
      loaded_cart = Cart.update_delivery_type!(cart, %{delivery_type: type}, scope: scope)
      PubSubNotifier.broadcast_cart_update(loaded_cart)
      {:noreply,
       socket
       |> assign(cart: loaded_cart)
       |> push_event("ph:capture", %{event: "delivery_type_changed", props: %{delivery_type: type, org_id: org.id}})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("start_checkout", _params, socket) do
    %{cart: cart, org: org} = socket.assigns

    {:noreply,
     socket
     |> assign(:checkout_step, :confirm)
     |> push_event("ph:capture", %{event: "checkout_started", props: %{item_count: socket.assigns.cart_count, org_id: org.id, delivery_type: cart && cart.delivery_type}})}
  end

  def handle_event("place_order", _params, %{assigns: %{store_open: false}} = socket) do
    {:noreply,
     put_flash(socket, :error, "We're currently closed. Please check back during business hours.")}
  end

  def handle_event("place_order", params, socket) do
    %{ash_scope: scope, cart: cart, org: org} = socket.assigns

    subtotal = order_subtotal(cart)
    tax_amount = order_tax_amount(subtotal, org.tax_rate)

    delivery_fee =
      if cart.delivery_type == :delivery,
        do: org.delivery_fee || Money.new(0, subtotal.currency),
        else: Money.new(0, subtotal.currency)

    {:ok, total_before_delivery} = Money.add(subtotal, tax_amount)
    {:ok, total_price} = Money.add(total_before_delivery, delivery_fee)

    delivery_address = params["delivery_address"]

    if cart.delivery_type == :delivery and
         not GeofenceChecker.within_zone?(org, delivery_address || %{}) do
      {:noreply, put_flash(socket, :error, "Sorry, your address is outside our delivery area.")}
    else
      order =
        Order.place_order!(
          %{
            customer_name: params["customer_name"],
            customer_email: params["customer_email"],
            notes: params["notes"],
            total_price: total_price,
            tax_amount: tax_amount,
            delivery_type: cart.delivery_type,
            delivery_fee: delivery_fee,
            delivery_address: delivery_address
          },
          scope: scope
        )

      Enum.each(cart.cart_items, fn item ->
        modifiers = order_find_modifiers(item)
        price = order_item_price(item, modifiers)

        modifiers_snapshot =
          Enum.map(modifiers, fn mod ->
            %{
              "name" => mod.name,
              "price" => Money.to_string!(mod.price_delta || Money.new!(0, price.currency))
            }
          end)

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
      Emails.send_order_confirmation(order)

      distinct_id =
        case socket.assigns[:current_user] do
          %{id: uid} -> uid
          _ -> scope.guest_session_id
        end

      SupervisedSlices.Analytics.capture("order_placed", distinct_id, %{
        order_id: order.id,
        delivery_type: cart.delivery_type,
        "$groups": %{organization: org.id}
      })

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
  end

  def handle_event("add_to_cart", %{"item_id" => item_id} = params, socket) do
    %{ash_scope: scope, cart: cart, org: org} = socket.assigns
    size_id = params["size_id"]
    modifier_ids = String.split(params["modifier_ids"] || "", ",", trim: true)

    cart = cart || Cart.create!(scope: scope)

    CartItem.add_to_cart!(
      %{
        cart_id: cart.id,
        menu_item_id: to_string(item_id),
        quantity: 1,
        selected_modifier_ids: modifier_ids,
        selected_size_id: if(size_id != "", do: to_string(size_id))
      },
      scope: scope
    )

    loaded_cart =
      Cart.get!(cart.id,
        scope: scope,
        load: [
          cart_items: [
            :selected_size,
            menu_item: [modifier_groups: [:modifiers]]
          ]
        ]
      )

    PubSubNotifier.broadcast_cart_update(loaded_cart)
    {cart_items_map, cart_count} = build_cart_state(loaded_cart)

    item_name =
      loaded_cart.cart_items
      |> Enum.find(&(to_string(&1.menu_item_id) == to_string(item_id)))
      |> case do
        %{menu_item: %{name: name}} -> name
        _ -> nil
      end

    {:noreply,
     socket
     |> assign(cart: loaded_cart, cart_items_map: cart_items_map, cart_count: cart_count)
     |> push_event("ph:capture", %{event: "item_added_to_cart", props: %{item_id: item_id, item_name: item_name, org_id: org.id}})
     |> push_patch(to: ~p"/menu/#{org.slug}")}
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

    # Determine DB operation
    {socket, db_op} =
      case {Map.get(socket.assigns.cart_items_map, key), delta} do
        {nil, 1} ->
          {socket, {:add, item_id, size_id, modifier_id}}

        {%{cart_item_id: cid, quantity: qty}, 1} ->
          {socket, {:update, cid, qty + 1}}

        {%{cart_item_id: cid, quantity: 1}, -1} ->
          {socket, {:remove, cid}}

        {%{cart_item_id: cid, quantity: qty}, -1} ->
          {socket, {:update, cid, qty - 1}}

        _ ->
          {socket, :noop}
      end

    if db_op == :noop do
      {:noreply, socket}
    else
      # Ensure cart exists synchronously
      {socket, cart} =
        case socket.assigns.cart do
          nil ->
            cart = Cart.create!(scope: socket.assigns.ash_scope)
            {assign(socket, cart: cart), cart}

          cart ->
            {socket, cart}
        end

      scope = socket.assigns.ash_scope

      case db_op do
        {:add, iid, sid, mid} ->
          CartItem.add_to_cart!(
            %{
              cart_id: cart.id,
              menu_item_id: iid,
              quantity: 1,
              selected_modifier_ids: if(mid, do: [mid], else: []),
              selected_size_id: sid
            },
            scope: scope
          )

        {:update, cid, new_qty} ->
          CartItem.get!(cid, scope: scope)
          |> CartItem.update_quantity!(%{quantity: new_qty}, scope: scope)

        {:remove, cid} ->
          CartItem.get!(cid, scope: scope)
          |> CartItem.destroy!(scope: scope)
      end

      loaded_cart =
        Cart.get!(cart.id,
          scope: scope,
          load: [
            cart_items: [
              :selected_size,
              menu_item: [modifier_groups: [:modifiers]]
            ]
          ]
        )

      PubSubNotifier.broadcast_cart_update(loaded_cart)
      {cart_items_map, cart_count} = build_cart_state(loaded_cart)

      {:noreply,
       socket
       |> assign(cart: loaded_cart, cart_items_map: cart_items_map, cart_count: cart_count)}
    end
  end

  def handle_event("remove_cart_item", %{"cart_item_id" => cart_item_id}, socket) do
    result =
      Enum.find(socket.assigns.cart_items_map, fn {_k, %{cart_item_id: cid}} ->
        to_string(cid) == cart_item_id
      end)

    socket =
      case result do
        {key, %{cart_item_id: cid}} -> do_remove_item(socket, cid, key)
        nil -> socket
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Cart helpers
  # ---------------------------------------------------------------------------

  defp do_remove_item(socket, cart_item_id, _key) do
    %{ash_scope: scope, cart: cart} = socket.assigns

    CartItem.get!(cart_item_id, scope: scope)
    |> CartItem.destroy!(scope: scope)

    refresh_cart(socket, cart)
  end

  defp refresh_cart(socket, cart) do
    %{ash_scope: scope} = socket.assigns

    loaded_cart =
      Cart.get!(cart.id,
        scope: scope,
        load: [
          cart_items: [
            :selected_size,
            menu_item: [modifier_groups: [:modifiers]]
          ]
        ]
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
    cart_load = [
      cart_items: [
        :selected_size,
        menu_item: [modifier_groups: [:modifiers]]
      ]
    ]

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

  defp order_find_modifiers(cart_item) do
    modifier_ids = MapSet.new(Enum.map(cart_item.selected_modifier_ids || [], &to_string/1))

    Enum.flat_map(cart_item.menu_item.modifier_groups || [], fn group ->
      Enum.filter(group.modifiers || [], &MapSet.member?(modifier_ids, to_string(&1.id)))
    end)
  end

  defp order_item_price(cart_item, modifiers) do
    base =
      case cart_item.selected_size do
        %{price: size_price} -> size_price
        _ -> cart_item.menu_item.price
      end

    Enum.reduce(modifiers, base, fn modifier, acc ->
      if modifier.price_delta do
        case Money.add(acc, modifier.price_delta) do
          {:ok, p} -> p
          _ -> acc
        end
      else
        acc
      end
    end)
  end

  defp order_subtotal(cart) do
    Enum.reduce(cart.cart_items, nil, fn item, acc ->
      modifiers = order_find_modifiers(item)
      line = Money.mult!(order_item_price(item, modifiers), item.quantity)
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

  defp upsell_suggestions(nil, _scope, _dismissed), do: []
  defp upsell_suggestions(_cart, _scope, true), do: []

  defp upsell_suggestions(cart, scope, false) do
    cart_item_ids = MapSet.new(cart.cart_items, & &1.menu_item_id)

    MenuItem.upsellable!(scope: scope, authorize?: false)
    |> Enum.reject(&MapSet.member?(cart_item_ids, &1.id))
    |> Enum.shuffle()
    |> Enum.take(3)
  end

  # ---------------------------------------------------------------------------
  # Template
  # ---------------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <header class="fixed top-0 w-full z-50 bg-background/80 backdrop-blur-md flex items-center gap-4 px-6 py-4 shadow-soft">
      <.link
        :if={@live_action == :show}
        id="back-button"
        patch={~p"/menu/#{@org.slug}"}
        phx-view-transition
        phx-click={JS.add_class("phx-click-loading", to: "self")}
        class="flex items-center justify-center w-11 h-11 rounded-full bg-surface-container-low hover:bg-surface-container transition-all text-on-surface active:scale-90 active:bg-surface-container-highest phx-click-loading:scale-90 phx-click-loading:opacity-60 phx-click-loading:bg-surface-container-highest"
        aria-label="Back to menu"
      >
        <span class="relative flex items-center justify-center w-5 h-5">
          <span class="phx-click-loading:!hidden">
            <span class="material-symbols-outlined !text-[20px] font-black">
              arrow_back
            </span>
          </span>
          <span class="hidden phx-click-loading:!flex absolute inset-0 items-center justify-center">
            <.icon name="hero-arrow-path" class="size-5 animate-spin" />
          </span>
        </span>
      </.link>
      <div class="flex items-center gap-3">
        <img
          :if={@org.logo_url}
          src={@org.logo_url}
          alt={@org.name}
          class="h-8 max-w-[120px] object-contain"
        />
        <h1 class="font-headline text-2xl font-black tracking-[-0.02em] text-on-surface leading-none">
          {@org.name}
        </h1>
      </div>
    </header>

    <div
      :if={!@store_open}
      class="mt-28 mx-6 bg-surface-container-high px-6 py-5 flex items-start gap-4"
    >
      <span class="material-symbols-outlined text-primary text-2xl mt-0.5">storefront</span>
      <div>
        <h3 class="font-headline text-lg font-bold text-on-surface leading-none">
          We're currently closed
        </h3>
        <p class="font-body text-sm text-on-surface-variant mt-2 leading-relaxed">
          You can browse the menu, but orders aren't being accepted right now. Check back soon!
        </p>
      </div>
    </div>

    <%!-- Menu index: skeleton while categories load, then the real list --%>
    <.menu_skeleton :if={@live_action == :index && @categories.loading} />
    <.live_component
      :if={@live_action == :index && @categories.ok?}
      module={SupervisedSlicesWeb.MenuLive.MenuComponent}
      id="menu"
      categories={@categories.result || []}
      cart_items_map={@cart_items_map}
      org={@org}
      store_open={@store_open}
    />

    <%!-- Item detail: skeleton only when navigating directly (no categories preloaded) --%>
    <.item_skeleton
      :if={@live_action == :show && @selected_item.loading && is_nil(@quick_item)}
      id={@selected_item_id}
      has_image={@selected_item_has_image}
    />
    <.live_component
      :if={@live_action == :show && ((@selected_item.ok? && @selected_item.result != nil) || not is_nil(@quick_item))}
      module={SupervisedSlicesWeb.MenuLive.ItemComponent}
      id="item"
      selected_item={@selected_item.result || @quick_item}
      cart_items_map={@cart_items_map}
      org={@org}
    />

    <.menu_nav :if={@live_action != :show} cart_count={@cart_count} org={@org} cart={@cart} />

    <.basket_drawer
      cart={@cart}
      show={@show_basket}
      checkout_step={@checkout_step}
      tax_rate={@org.tax_rate}
      org={@org}
      store_open={@store_open}
      upsell_suggestions={upsell_suggestions(@cart, @ash_scope, @upsells_dismissed)}
    />

    <div class="fixed top-[15%] right-[-30px] opacity-[0.03] pointer-events-none transform rotate-[25deg] select-none hidden lg:block text-on-surface z-[-1]">
      <span class="material-symbols-outlined" style="font-size: 180px;">local_pizza</span>
    </div>
    <div class="fixed bottom-[20%] left-[-40px] opacity-[0.04] pointer-events-none transform -rotate-[15deg] select-none hidden lg:block text-on-surface z-[-1]">
      <span class="material-symbols-outlined" style="font-size: 200px;">egg</span>
    </div>
    <div class="fixed top-[45%] left-[-20px] opacity-[0.02] pointer-events-none transform rotate-[10deg] select-none hidden lg:block text-on-surface z-[-1]">
      <span class="material-symbols-outlined" style="font-size: 140px;">spa</span>
    </div>
    <div class="fixed bottom-[10%] right-[-10px] opacity-[0.03] pointer-events-none transform -rotate-[20deg] select-none hidden lg:block text-on-surface z-[-1]">
      <span class="material-symbols-outlined" style="font-size: 160px;">skillet</span>
    </div>
    <div
      class="fixed inset-0 pointer-events-none opacity-[0.02] mix-blend-multiply z-[-1]"
      style="background-image: url('https://www.transparenttextures.com/patterns/handmade-paper.png');"
    >
    </div>
    <div class="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 pointer-events-none opacity-[0.015] font-headline text-[25vw] font-black tracking-tighter leading-none select-none z-[-1] whitespace-nowrap italic -rotate-12">
      SUPERVISED SLICES
    </div>
    """
  end

  defp menu_nav(assigns) do
    ~H"""
    <nav class="fixed bottom-8 left-0 right-0 flex justify-center md:justify-end px-6 md:px-12 z-50 pointer-events-none">
      <div class="pointer-events-auto w-full max-w-lg md:max-w-md">
        <button
          phx-click={open_basket_js() |> JS.push("toggle_basket")}
          class={[
            "w-full flex items-center justify-between bg-gradient-to-br from-primary to-primary-container text-on-primary rounded-xl px-8 py-5",
            "shadow-soft hover:scale-[1.03] hover:shadow-lg",
            "transition-all duration-300 active:scale-95 group"
          ]}
        >
          <div class="flex items-center gap-4">
            <div class="relative">
              <span class="material-symbols-outlined font-black !text-[26px]">shopping_bag</span>
              <div
                :if={@cart_count > 0}
                class="absolute -top-1.5 -right-1.5 w-5 h-5 bg-white text-primary rounded-full flex items-center justify-center text-[10px] font-black shadow-sm group-hover:scale-110 transition-transform"
              >
                {@cart_count}
              </div>
            </div>
            <span class="font-headline text-base font-black tracking-tight uppercase">
              View Basket
            </span>
          </div>
          <div class="flex items-center gap-3">
            <span
              :if={@cart_count > 0}
              class="font-headline text-xl font-black opacity-90 group-hover:scale-110 transition-transform"
            >
              {basket_subtotal_string(@cart)}
            </span>
            <span class="material-symbols-outlined !text-[24px] font-black group-hover:translate-x-1 transition-transform">
              chevron_right
            </span>
          </div>
        </button>
      </div>
    </nav>
    """
  end

  defp menu_skeleton(assigns) do
    ~H"""
    <main class="bg-background min-h-screen pt-32 pb-32 px-4 max-w-2xl mx-auto">
      <section class="mb-16">
        <div class="flex items-end justify-between mb-8 px-2">
          <div class="h-9 w-48 bg-surface-container animate-pulse rounded" />
          <div class="h-3 w-24 bg-surface-container-low animate-pulse rounded" />
        </div>
        <div class="grid grid-cols-2 gap-x-4 gap-y-6">
          <div class="rounded-xl overflow-hidden bg-surface-container animate-pulse">
            <div class="aspect-square" />
            <div class="p-4 space-y-2">
              <div class="h-5 w-3/4 bg-surface-container-low animate-pulse rounded" />
              <div class="h-3 w-full bg-surface-container-low animate-pulse rounded" />
              <div class="h-3 w-2/3 bg-surface-container-low animate-pulse rounded" />
            </div>
          </div>
          <div class="rounded-xl overflow-hidden bg-surface-container animate-pulse">
            <div class="aspect-square" />
            <div class="p-4 space-y-2">
              <div class="h-5 w-3/4 bg-surface-container-low animate-pulse rounded" />
              <div class="h-3 w-full bg-surface-container-low animate-pulse rounded" />
              <div class="h-3 w-2/3 bg-surface-container-low animate-pulse rounded" />
            </div>
          </div>
          <div class="col-span-2 h-20 bg-surface-container-low animate-pulse rounded-xl" />
          <div class="col-span-2 h-20 bg-surface-container-low animate-pulse rounded-xl" />
        </div>
      </section>
      <section class="mb-16">
        <div class="flex items-end justify-between mb-8 px-2">
          <div class="h-9 w-36 bg-surface-container animate-pulse rounded" />
          <div class="h-3 w-24 bg-surface-container-low animate-pulse rounded" />
        </div>
        <div class="grid grid-cols-2 gap-x-4 gap-y-6">
          <div class="rounded-xl overflow-hidden bg-surface-container animate-pulse">
            <div class="aspect-square" />
            <div class="p-4 space-y-2">
              <div class="h-5 w-3/4 bg-surface-container-low animate-pulse rounded" />
              <div class="h-3 w-full bg-surface-container-low animate-pulse rounded" />
            </div>
          </div>
          <div class="rounded-xl overflow-hidden bg-surface-container animate-pulse">
            <div class="aspect-square" />
            <div class="p-4 space-y-2">
              <div class="h-5 w-3/4 bg-surface-container-low animate-pulse rounded" />
              <div class="h-3 w-full bg-surface-container-low animate-pulse rounded" />
            </div>
          </div>
          <div class="col-span-2 h-20 bg-surface-container-low animate-pulse rounded-xl" />
        </div>
      </section>
    </main>
    """
  end

  defp item_skeleton(assigns) do
    ~H"""
    <div class="bg-surface min-h-screen text-on-surface antialiased">
      <main class="pt-[72px] pb-44">
        <%!-- Hero image placeholder --%>
        <div
          :if={@has_image}
          class="relative w-full aspect-[4/5] md:aspect-video overflow-hidden bg-surface-container animate-pulse"
          style={"view-transition-name: item-img-#{@id};"}
        />

        <div class={["px-8 space-y-12 max-w-3xl mx-auto relative z-10", @has_image && "mt-[-100px]", !@has_image && "mt-12"]}>
          <%!-- Name & description --%>
          <div class="space-y-3 pt-4">
            <div class="h-12 w-3/4 bg-surface-container animate-pulse rounded" />
            <div
              class="h-4 w-full bg-surface-container-low animate-pulse rounded"
              style={"view-transition-name: item-desc-#{@id};"}
            />
            <div class="h-4 w-2/3 bg-surface-container-low animate-pulse rounded" />
          </div>

          <%!-- Size selector --%>
          <div class="space-y-6">
            <div class="flex items-baseline justify-between">
              <div class="h-7 w-44 bg-surface-container animate-pulse rounded" />
              <div class="h-3 w-24 bg-surface-container-low animate-pulse rounded" />
            </div>
            <div class="flex gap-4 overflow-x-auto pb-4">
              <div class="w-28 h-36 bg-surface-container-low animate-pulse rounded-xl flex-shrink-0" />
              <div class="w-28 h-36 bg-surface-container-low animate-pulse rounded-xl flex-shrink-0" />
              <div class="w-28 h-36 bg-surface-container-low animate-pulse rounded-xl flex-shrink-0" />
            </div>
          </div>

          <%!-- Modifier group --%>
          <div class="space-y-6">
            <div class="flex items-baseline justify-between">
              <div class="h-7 w-52 bg-surface-container animate-pulse rounded" />
              <div class="h-3 w-20 bg-surface-container-low animate-pulse rounded" />
            </div>
            <div class="grid grid-cols-1 gap-3">
              <div class="h-16 bg-surface-container-low animate-pulse rounded-xl" />
              <div class="h-16 bg-surface-container-low animate-pulse rounded-xl" />
              <div class="h-16 bg-surface-container-low animate-pulse rounded-xl" />
            </div>
          </div>
        </div>
      </main>

      <%!-- Sticky footer placeholder --%>
      <footer class="fixed bottom-0 left-0 w-full bg-surface/90 backdrop-blur-xl px-8 py-6 z-50 shadow-[0_-10px_40px_rgba(28,28,24,0.06)]">
        <div class="max-w-3xl mx-auto flex items-center justify-between gap-6">
          <div class="space-y-2">
            <div class="h-3 w-16 bg-surface-container-low animate-pulse rounded" />
            <div class="h-8 w-28 bg-surface-container animate-pulse rounded" />
          </div>
          <div class="flex-1 h-14 bg-surface-container animate-pulse rounded-md" />
        </div>
      </footer>
    </div>
    """
  end

  defp open_basket_js do
    JS.remove_class("invisible pointer-events-none", to: "#basket-wrapper")
    |> JS.add_class("visible", to: "#basket-wrapper")
    |> JS.add_class("opacity-100", to: "#basket-backdrop")
    |> JS.remove_class("opacity-0", to: "#basket-backdrop")
    |> JS.remove_class("translate-y-full", to: "#basket-panel")
    |> JS.remove_class("md:translate-x-full", to: "#basket-panel")
    |> JS.add_class("translate-y-0", to: "#basket-panel")
    |> JS.add_class("md:translate-x-0", to: "#basket-panel")
  end
end
