defmodule SupervisedSlicesWeb.AdminLive do
  use SupervisedSlicesWeb, :live_view

  on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_required}

  alias SupervisedSlices.Cart.Cart

  alias SupervisedSlices.Menu.{
    Category,
    MenuItem,
    MenuItemSize,
    MenuItemModifierGroup,
    MenuItemModifier,
    MenuItemModifierGroupLink,
    SizeGroup
  }

  alias SupervisedSlices.Orders.Order
  alias SupervisedSlices.{OrgPresence, PubSubNotifier}

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  def mount(_params, _session, socket) do
    %{org: org, ash_scope: scope} = socket.assigns

    orders = load_active_orders(scope)
    active_carts = load_active_carts(scope)
    visitor_count = org.id |> OrgPresence.list_visitors() |> map_size()
    categories = load_categories(scope)
    size_groups = load_size_groups(scope)
    modifier_groups = load_modifier_groups(scope)

    if connected?(socket) do
      PubSubNotifier.subscribe_to_org_orders(org.id)
      PubSubNotifier.subscribe_to_org_carts(org.id)
      OrgPresence.subscribe(org.id)
    end

    {:ok,
     socket
     |> assign(:visitor_count, visitor_count)
     |> assign(:active_carts, active_carts)
     |> assign(:categories, categories)
     |> assign(:size_groups, size_groups)
     |> assign(:modifier_groups, modifier_groups)
     |> assign(:editing_item_id, nil)
     |> assign(:adding_to_category_id, nil)
     |> assign(:creating_category, false)
     |> assign(:creating_size_group, false)
     |> assign(:adding_size_to_group_id, nil)
     |> assign(:creating_modifier_group, false)
     |> assign(:adding_modifier_to_group_id, nil)
     |> assign(:assigning_modifier_group_to_item_id, nil)
     |> assign(:page_title, "Kitchen Command")
     |> stream(:orders, orders)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub – Orders
  # ---------------------------------------------------------------------------

  def handle_info({:new_order, order}, socket) do
    loaded = reload_order(order, socket.assigns.ash_scope)
    {:noreply, stream_insert(socket, :orders, loaded, at: 0)}
  end

  def handle_info({:order_updated, order}, socket) do
    if order.status in [:completed, :cancelled] do
      {:noreply, stream_delete(socket, :orders, order)}
    else
      loaded = reload_order(order, socket.assigns.ash_scope)
      {:noreply, stream_insert(socket, :orders, loaded)}
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub – Carts
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # PubSub – Presence
  # ---------------------------------------------------------------------------

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    count = socket.assigns.org.id |> OrgPresence.list_visitors() |> map_size()
    {:noreply, assign(socket, :visitor_count, count)}
  end

  # ---------------------------------------------------------------------------
  # Order events
  # ---------------------------------------------------------------------------

  def handle_event("advance_order", %{"id" => order_id}, socket) do
    %{ash_scope: scope} = socket.assigns
    order = Order.get!(order_id, scope: scope)
    Order.update_status!(order, %{status: next_status(order.status)}, scope: scope)
    {:noreply, socket}
  end

  def handle_event("cancel_order", %{"id" => order_id}, socket) do
    %{ash_scope: scope} = socket.assigns
    order = Order.get!(order_id, scope: scope)
    Order.update_status!(order, %{status: :cancelled}, scope: scope)
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Menu editor – item events
  # ---------------------------------------------------------------------------

  def handle_event("edit_item", %{"id" => id}, socket) do
    {:noreply,
     assign(socket,
       editing_item_id: id,
       adding_to_category_id: nil,
       assigning_modifier_group_to_item_id: nil
     )}
  end

  def handle_event("add_item", %{"category_id" => id}, socket) do
    {:noreply, assign(socket, adding_to_category_id: id, editing_item_id: nil)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     assign(socket,
       editing_item_id: nil,
       adding_to_category_id: nil,
       adding_size_to_group_id: nil,
       adding_modifier_to_group_id: nil,
       assigning_modifier_group_to_item_id: nil
     )}
  end

  def handle_event("save_item", %{"item" => params}, socket) do
    %{ash_scope: scope} = socket.assigns

    size_group_id = case params["size_group_id"] do
      "" -> nil
      nil -> nil
      v -> v
    end

    attrs = %{
      name: params["name"],
      description: params["description"],
      price: parse_money(params["price"]),
      image_url: params["image_url"],
      sort_order: String.to_integer(params["sort_order"] || "0"),
      size_group_id: size_group_id
    }

    MenuItem.get!(params["id"], scope: scope)
    |> MenuItem.update!(attrs, scope: scope)

    categories = load_categories(scope)
    {:noreply, assign(socket, categories: categories, editing_item_id: nil)}
  end

  def handle_event("toggle_available", %{"id" => id}, socket) do
    %{ash_scope: scope} = socket.assigns
    item = MenuItem.get!(id, scope: scope)
    MenuItem.update!(item, %{available: !item.available}, scope: scope)
    categories = load_categories(scope)
    {:noreply, assign(socket, :categories, categories)}
  end

  def handle_event("create_item", %{"item" => params}, socket) do
    %{ash_scope: scope} = socket.assigns

    size_group_id = case params["size_group_id"] do
      "" -> nil
      nil -> nil
      v -> v
    end

    MenuItem.create!(
      %{
        name: params["name"],
        description: params["description"],
        price: parse_money(params["price"]),
        image_url: params["image_url"],
        sort_order: String.to_integer(params["sort_order"] || "0"),
        category_id: params["category_id"],
        size_group_id: size_group_id
      },
      scope: scope
    )

    categories = load_categories(scope)
    {:noreply, assign(socket, categories: categories, adding_to_category_id: nil)}
  end

  def handle_event("edit_category", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_item_id: "cat:#{id}", adding_to_category_id: nil)}
  end

  def handle_event("add_category", _params, socket) do
    {:noreply,
     assign(socket,
       creating_category: true,
       editing_item_id: nil,
       adding_to_category_id: nil
     )}
  end

  def handle_event("cancel_add_category", _params, socket) do
    {:noreply, assign(socket, :creating_category, false)}
  end

  def handle_event("create_category", %{"category" => params}, socket) do
    %{ash_scope: scope} = socket.assigns

    Category.create!(
      %{
        name: params["name"],
        sort_order: String.to_integer(params["sort_order"] || "0")
      },
      scope: scope
    )

    categories = load_categories(scope)
    {:noreply, assign(socket, categories: categories, creating_category: false)}
  end

  def handle_event("save_category", %{"category" => params}, socket) do
    %{ash_scope: scope} = socket.assigns

    Category.get!(params["id"], scope: scope)
    |> Category.update!(
      %{
        name: params["name"],
        sort_order: String.to_integer(params["sort_order"] || "0")
      },
      scope: scope
    )

    categories = load_categories(scope)
    {:noreply, assign(socket, categories: categories, editing_item_id: nil)}
  end

  # ---------------------------------------------------------------------------
  # Size Group events
  # ---------------------------------------------------------------------------

  def handle_event("add_size_group", _params, socket) do
    {:noreply, assign(socket, creating_size_group: true)}
  end

  def handle_event("cancel_add_size_group", _params, socket) do
    {:noreply, assign(socket, creating_size_group: false)}
  end

  def handle_event("create_size_group", %{"size_group" => params}, socket) do
    %{ash_scope: scope} = socket.assigns

    SizeGroup.create!(
      %{name: params["name"]},
      scope: scope
    )

    size_groups = load_size_groups(scope)
    {:noreply, assign(socket, size_groups: size_groups, creating_size_group: false)}
  end

  def handle_event("delete_size_group", %{"id" => id}, socket) do
    %{ash_scope: scope} = socket.assigns
    SizeGroup.get!(id, scope: scope) |> SizeGroup.destroy!(scope: scope)
    size_groups = load_size_groups(scope)
    categories = load_categories(scope)
    {:noreply, assign(socket, size_groups: size_groups, categories: categories)}
  end

  def handle_event("add_size", %{"group_id" => group_id}, socket) do
    {:noreply,
     assign(socket,
       adding_size_to_group_id: group_id,
       adding_modifier_to_group_id: nil
     )}
  end

  def handle_event("cancel_add_size", _params, socket) do
    {:noreply, assign(socket, :adding_size_to_group_id, nil)}
  end

  def handle_event("create_size", %{"size" => params}, socket) do
    %{ash_scope: scope} = socket.assigns

    MenuItemSize.create!(
      %{
        name: params["name"],
        price: Money.new!(:CAD, Decimal.new(params["price"] || "0")),
        size_group_id: params["size_group_id"]
      },
      scope: scope
    )

    size_groups = load_size_groups(scope)
    {:noreply, assign(socket, size_groups: size_groups, adding_size_to_group_id: nil)}
  end

  def handle_event("delete_size", %{"id" => id}, socket) do
    %{ash_scope: scope} = socket.assigns
    MenuItemSize.get!(id, scope: scope) |> MenuItemSize.destroy!(scope: scope)
    size_groups = load_size_groups(scope)
    {:noreply, assign(socket, :size_groups, size_groups)}
  end

  # ---------------------------------------------------------------------------
  # Modifier Group events
  # ---------------------------------------------------------------------------

  def handle_event("add_modifier_group", _params, socket) do
    {:noreply,
     assign(socket,
       creating_modifier_group: true,
       adding_modifier_to_group_id: nil
     )}
  end

  def handle_event("cancel_add_modifier_group", _params, socket) do
    {:noreply, assign(socket, creating_modifier_group: false)}
  end

  def handle_event("create_modifier_group", %{"group" => params}, socket) do
    %{ash_scope: scope} = socket.assigns

    MenuItemModifierGroup.create!(
      %{
        name: params["name"],
        required: Map.get(params, "required") == "true"
      },
      scope: scope
    )

    modifier_groups = load_modifier_groups(scope)
    {:noreply, assign(socket, modifier_groups: modifier_groups, creating_modifier_group: false)}
  end

  def handle_event("delete_modifier_group", %{"id" => id}, socket) do
    %{ash_scope: scope} = socket.assigns

    group = MenuItemModifierGroup.get!(id, scope: scope, load: :modifiers)
    Enum.each(group.modifiers, &MenuItemModifier.destroy!(&1, scope: scope))
    MenuItemModifierGroup.destroy!(group, scope: scope)

    modifier_groups = load_modifier_groups(scope)
    categories = load_categories(scope)
    {:noreply, assign(socket, modifier_groups: modifier_groups, categories: categories)}
  end

  # ---------------------------------------------------------------------------
  # Modifier events
  # ---------------------------------------------------------------------------

  def handle_event("add_modifier", %{"group_id" => group_id}, socket) do
    {:noreply,
     assign(socket,
       adding_modifier_to_group_id: group_id,
       adding_size_to_group_id: nil
     )}
  end

  def handle_event("cancel_add_modifier", _params, socket) do
    {:noreply, assign(socket, :adding_modifier_to_group_id, nil)}
  end

  def handle_event("create_modifier", %{"modifier" => params}, socket) do
    %{ash_scope: scope} = socket.assigns

    MenuItemModifier.create!(
      %{
        name: params["name"],
        price_delta: parse_money(params["price_delta"]),
        modifier_group_id: params["modifier_group_id"]
      },
      scope: scope
    )

    modifier_groups = load_modifier_groups(scope)
    {:noreply, assign(socket, modifier_groups: modifier_groups, adding_modifier_to_group_id: nil)}
  end

  def handle_event("delete_modifier", %{"id" => id}, socket) do
    %{ash_scope: scope} = socket.assigns
    MenuItemModifier.get!(id, scope: scope) |> MenuItemModifier.destroy!(scope: scope)
    modifier_groups = load_modifier_groups(scope)
    {:noreply, assign(socket, :modifier_groups, modifier_groups)}
  end

  # ---------------------------------------------------------------------------
  # Item <-> Modifier Group assignment
  # ---------------------------------------------------------------------------

  def handle_event("assign_modifier_group_panel", %{"item_id" => item_id}, socket) do
    {:noreply,
     assign(socket,
       assigning_modifier_group_to_item_id: item_id,
       editing_item_id: nil
     )}
  end

  def handle_event("cancel_assign_modifier_group", _params, socket) do
    {:noreply, assign(socket, assigning_modifier_group_to_item_id: nil)}
  end

  def handle_event("assign_modifier_group", %{"item_id" => item_id, "group_id" => group_id}, socket) do
    %{ash_scope: scope} = socket.assigns

    MenuItemModifierGroupLink.assign!(
      %{menu_item_id: item_id, modifier_group_id: group_id},
      scope: scope
    )

    categories = load_categories(scope)
    {:noreply, assign(socket, categories: categories)}
  end

  def handle_event("remove_item_modifier_group", %{"item_id" => item_id, "group_id" => group_id}, socket) do
    %{ash_scope: scope} = socket.assigns

    links =
      Ash.read!(SupervisedSlices.Menu.MenuItemModifierGroupLink,
        scope: scope,
        authorize?: false
      )

    link =
      Enum.find(links, fn l ->
        to_string(l.menu_item_id) == item_id and to_string(l.modifier_group_id) == group_id
      end)

    if link do
      MenuItemModifierGroupLink.unassign!(link, scope: scope)
    end

    categories = load_categories(scope)
    {:noreply, assign(socket, categories: categories)}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_active_orders(scope) do
    Order.active!(scope: scope, authorize?: false)
  end

  defp load_active_carts(scope) do
    Cart.active_for_org!(scope: scope)
  end

  defp load_categories(scope) do
    Category.active!(
      scope: scope,
      load: [menu_items: [modifier_groups: [:modifiers], size_group: [:sizes]]]
    )
  end

  defp load_size_groups(scope) do
    SizeGroup.list!(scope: scope, load: [:sizes], authorize?: false)
  end

  defp load_modifier_groups(scope) do
    MenuItemModifierGroup.list!(scope: scope, load: [:modifiers], authorize?: false)
  end

  defp reload_order(order, scope) do
    Order.get!(order.id, scope: scope, load: :order_items, authorize?: false)
  end

  defp parse_money(nil), do: nil
  defp parse_money(""), do: nil

  defp parse_money(str) do
    case Decimal.parse(str) do
      {d, ""} -> Money.new!(:CAD, d)
      _ -> nil
    end
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

  defp next_status(:pending), do: :confirmed
  defp next_status(:confirmed), do: :preparing
  defp next_status(:preparing), do: :ready
  defp next_status(:ready), do: :completed
  defp next_status(s), do: s

  defp next_status_label(:pending), do: "Confirm"
  defp next_status_label(:confirmed), do: "Start Preparing"
  defp next_status_label(:preparing), do: "Mark Ready"
  defp next_status_label(:ready), do: "Complete"
  defp next_status_label(_), do: nil

  defp time_ago(nil), do: ""

  defp time_ago(datetime) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      true -> "#{div(seconds, 3600)}h ago"
    end
  end

  defp order_number(order) do
    order.id |> String.slice(-4, 4) |> String.upcase()
  end

  defp status_badge_class(:pending),
    do: "bg-primary-fixed text-on-primary-fixed-variant"

  defp status_badge_class(:confirmed),
    do: "bg-primary-fixed text-on-primary-fixed-variant"

  defp status_badge_class(:preparing),
    do: "bg-tertiary-fixed text-on-tertiary-fixed-variant"

  defp status_badge_class(:ready),
    do: "bg-secondary-fixed text-on-secondary-fixed-variant"

  defp status_badge_class(_),
    do: "bg-surface-container text-on-surface-variant"

  defp status_label(:pending), do: "New"
  defp status_label(:confirmed), do: "Confirmed"
  defp status_label(:preparing), do: "Preparing"
  defp status_label(:ready), do: "Ready"
  defp status_label(:completed), do: "Done"
  defp status_label(:cancelled), do: "Cancelled"

  defp format_money(money) do
    Money.to_string!(money)
  rescue
    _ -> "#{money}"
  end

  defp money_amount(nil), do: "0.00"
  defp money_amount(money), do: Decimal.to_string(money.amount, :normal)
end
