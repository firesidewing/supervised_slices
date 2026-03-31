defmodule SupervisedSlicesWeb.MenuLive.Index do
  use SupervisedSlicesWeb, :live_view

  on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_optional}

  alias SupervisedSlices.Accounts.GuestSession
  alias SupervisedSlices.Cart.Cart
  alias SupervisedSlices.Cart.CartItem
  alias SupervisedSlices.Menu.Category
  alias SupervisedSlices.Menu.MenuItem
  alias SupervisedSlices.OrgPresence
  alias SupervisedSlices.PubSubNotifier
  alias SupervisedSlices.Orgs.Organization

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  def mount(%{"org_slug" => slug}, session, socket) do
    org =
      Organization
      |> Ash.Query.for_read(:by_slug, %{slug: slug})
      |> Ash.read_one!(authorize?: false)

    categories =
      Category
      |> Ash.Query.for_read(:active)
      |> Ash.Query.load(menu_items: [modifier_groups: [:modifiers]])
      |> Ash.read!(tenant: org.id, authorize?: false)

    session_id = session["guest_session_id"]
    actor = build_actor(socket.assigns.current_user, session_id)

    cart = load_cart(org, actor, session_id)
    {cart_items_map, cart_count} = build_cart_state(cart)

    if connected?(socket) do
      OrgPresence.track_visitor(self(), org.id, session_id || "anon", %{})
    end

    {:ok,
     socket
     |> assign(:org, org)
     |> assign(:categories, categories)
     |> assign(:cart, cart)
     |> assign(:cart_items_map, cart_items_map)
     |> assign(:cart_count, cart_count)
     |> assign(:session_id, session_id)
     |> assign(:actor, actor)
     |> assign(:selected_item, nil)
     |> assign(:page_title, org.name)}
  end

  # ---------------------------------------------------------------------------
  # handle_params – switch between :index and :show live actions
  # ---------------------------------------------------------------------------

  def handle_params(%{"id" => id}, _uri, socket) do
    item =
      Ash.get!(MenuItem, id, tenant: socket.assigns.org.id, authorize?: false)
      |> Ash.load!([modifier_groups: [:modifiers]],
        tenant: socket.assigns.org.id,
        authorize?: false
      )

    {:noreply, assign(socket, :selected_item, item)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :selected_item, nil)}
  end

  # ---------------------------------------------------------------------------
  # Cart events
  # ---------------------------------------------------------------------------

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
    %{org: org, actor: actor, session_id: session_id, cart: cart} = socket.assigns

    cart =
      cart ||
        Cart
        |> Ash.Changeset.for_create(:create, %{session_id: session_id})
        |> Ash.create!(tenant: org.id, actor: actor)

    modifier_ids = if modifier_id, do: [modifier_id], else: []

    CartItem
    |> Ash.Changeset.for_create(:add_to_cart, %{
      cart_id: cart.id,
      menu_item_id: item_id,
      quantity: 1,
      selected_modifier_ids: modifier_ids
    })
    |> Ash.create!(tenant: org.id, actor: actor)

    refresh_cart(socket, cart)
  end

  defp do_update_quantity(socket, cart_item_id, key, new_qty) do
    %{org: org, actor: actor, cart_items_map: map} = socket.assigns

    Ash.get!(CartItem, cart_item_id, tenant: org.id, actor: actor)
    |> Ash.Changeset.for_update(:update_quantity, %{quantity: new_qty})
    |> Ash.update!(tenant: org.id, actor: actor)

    new_map = Map.update!(map, key, &%{&1 | quantity: new_qty})
    cart_count = count_cart_items(new_map)
    assign(socket, cart_items_map: new_map, cart_count: cart_count)
  end

  defp do_remove_item(socket, cart_item_id, key) do
    %{org: org, actor: actor, cart_items_map: map} = socket.assigns

    Ash.get!(CartItem, cart_item_id, tenant: org.id, actor: actor)
    |> Ash.destroy!(tenant: org.id, actor: actor)

    new_map = Map.delete(map, key)
    cart_count = count_cart_items(new_map)
    assign(socket, cart_items_map: new_map, cart_count: cart_count)
  end

  defp refresh_cart(socket, cart) do
    %{org: org, actor: actor} = socket.assigns

    loaded_cart =
      Ash.get!(Cart, cart.id, tenant: org.id, actor: actor)
      |> Ash.load!(:cart_items, tenant: org.id, actor: actor)

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

  defp build_actor(nil, session_id), do: %GuestSession{session_id: session_id}
  defp build_actor(user, _session_id), do: user

  defp load_cart(_org, _actor, nil), do: nil

  defp load_cart(org, actor, session_id) do
    Cart
    |> Ash.Query.for_read(:active_for_session, %{session_id: session_id})
    |> Ash.Query.load(:cart_items)
    |> Ash.read_one(tenant: org.id, actor: actor)
    |> case do
      {:ok, cart} -> cart
      _ -> nil
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
