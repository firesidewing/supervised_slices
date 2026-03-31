defmodule SupervisedSlicesWeb.AdminLive do
  use SupervisedSlicesWeb, :live_view

  on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_required}

  alias SupervisedSlices.Cart.Cart
  alias SupervisedSlices.Menu.{Category, MenuItem}
  alias SupervisedSlices.Orders.Order
  alias SupervisedSlices.Orgs.Organization
  alias SupervisedSlices.{OrgPresence, PubSubNotifier}

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  def mount(%{"org_slug" => slug}, _session, socket) do
    org =
      Organization
      |> Ash.Query.for_read(:by_slug, %{slug: slug})
      |> Ash.read_one!(authorize?: false)

    user = socket.assigns.current_user

    orders = load_active_orders(org, user)
    active_carts = load_active_carts(org, user)
    visitor_count = org.id |> OrgPresence.list_visitors() |> map_size()
    categories = load_categories(org, user)

    if connected?(socket) do
      PubSubNotifier.subscribe_to_org_orders(org.id)
      PubSubNotifier.subscribe_to_org_carts(org.id)
      OrgPresence.subscribe(org.id)
    end

    {:ok,
     socket
     |> assign(:org, org)
     |> assign(:current_user, user)
     |> assign(:visitor_count, visitor_count)
     |> assign(:active_carts, active_carts)
     |> assign(:categories, categories)
     |> assign(:editing_item_id, nil)
     |> assign(:adding_to_category_id, nil)
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
    %{org: org, current_user: user} = socket.assigns
    loaded = reload_order(order, org, user)
    {:noreply, stream_insert(socket, :orders, loaded, at: 0)}
  end

  def handle_info({:order_updated, order}, socket) do
    if order.status in [:completed, :cancelled] do
      {:noreply, stream_delete(socket, :orders, order)}
    else
      %{org: org, current_user: user} = socket.assigns
      loaded = reload_order(order, org, user)
      {:noreply, stream_insert(socket, :orders, loaded)}
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub – Carts
  # ---------------------------------------------------------------------------

  def handle_info({:cart_updated, cart}, socket) do
    %{org: org, current_user: user} = socket.assigns

    full_cart =
      case cart.status do
        :active ->
          Ash.get!(Cart, cart.id, tenant: org.id, actor: user)
          |> Ash.load!([cart_items: [:menu_item]], tenant: org.id, actor: user)

        _ ->
          cart
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
    %{org: org, current_user: user} = socket.assigns

    order = Ash.get!(Order, order_id, tenant: org.id, actor: user)
    next = next_status(order.status)

    order
    |> Ash.Changeset.for_update(:update_status, %{status: next})
    |> Ash.update!(tenant: org.id, actor: user)

    # PubSub will trigger handle_info({:order_updated, ...}) to update the stream
    {:noreply, socket}
  end

  def handle_event("cancel_order", %{"id" => order_id}, socket) do
    %{org: org, current_user: user} = socket.assigns

    order = Ash.get!(Order, order_id, tenant: org.id, actor: user)

    order
    |> Ash.Changeset.for_update(:update_status, %{status: :cancelled})
    |> Ash.update!(tenant: org.id, actor: user)

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Menu editor events
  # ---------------------------------------------------------------------------

  def handle_event("edit_item", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_item_id: id, adding_to_category_id: nil)}
  end

  def handle_event("add_item", %{"category_id" => id}, socket) do
    {:noreply, assign(socket, adding_to_category_id: id, editing_item_id: nil)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_item_id: nil, adding_to_category_id: nil)}
  end

  def handle_event("save_item", %{"item" => params}, socket) do
    %{org: org, current_user: user} = socket.assigns
    item_id = params["id"]

    item = Ash.get!(MenuItem, item_id, tenant: org.id, actor: user)

    attrs = %{
      name: params["name"],
      description: params["description"],
      price: parse_money(item.price, params["price"]),
      image_url: params["image_url"],
      sort_order: String.to_integer(params["sort_order"] || "0")
    }

    item
    |> Ash.Changeset.for_update(:update, attrs)
    |> Ash.update!(tenant: org.id, actor: user)

    categories = load_categories(org, user)
    {:noreply, assign(socket, categories: categories, editing_item_id: nil)}
  end

  def handle_event("toggle_available", %{"id" => id}, socket) do
    %{org: org, current_user: user} = socket.assigns

    item = Ash.get!(MenuItem, id, tenant: org.id, actor: user)

    item
    |> Ash.Changeset.for_update(:update, %{available: !item.available})
    |> Ash.update!(tenant: org.id, actor: user)

    categories = load_categories(org, user)
    {:noreply, assign(socket, :categories, categories)}
  end

  def handle_event("create_item", %{"item" => params}, socket) do
    %{org: org, current_user: user} = socket.assigns
    category_id = params["category_id"]

    price = Money.new!(:USD, Decimal.new(params["price"] || "0"))

    MenuItem
    |> Ash.Changeset.for_create(:create, %{
      name: params["name"],
      description: params["description"],
      price: price,
      image_url: params["image_url"],
      sort_order: String.to_integer(params["sort_order"] || "0"),
      category_id: category_id
    })
    |> Ash.create!(tenant: org.id, actor: user)

    categories = load_categories(org, user)
    {:noreply, assign(socket, categories: categories, adding_to_category_id: nil)}
  end

  def handle_event("edit_category", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_item_id: "cat:#{id}", adding_to_category_id: nil)}
  end

  def handle_event("save_category", %{"category" => params}, socket) do
    %{org: org, current_user: user} = socket.assigns
    cat_id = params["id"]

    cat = Ash.get!(Category, cat_id, tenant: org.id, actor: user)

    cat
    |> Ash.Changeset.for_update(:update, %{
      name: params["name"],
      sort_order: String.to_integer(params["sort_order"] || "0")
    })
    |> Ash.update!(tenant: org.id, actor: user)

    categories = load_categories(org, user)
    {:noreply, assign(socket, categories: categories, editing_item_id: nil)}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_active_orders(org, user) do
    Order
    |> Ash.Query.for_read(:active)
    |> Ash.read!(tenant: org.id, actor: user)
  rescue
    _ -> []
  end

  defp load_active_carts(org, user) do
    Cart
    |> Ash.Query.for_read(:active_for_org)
    |> Ash.read!(tenant: org.id, actor: user)
  rescue
    _ -> []
  end

  defp load_categories(org, user) do
    Category
    |> Ash.Query.for_read(:active)
    |> Ash.Query.load(menu_items: [modifier_groups: [:modifiers]])
    |> Ash.read!(tenant: org.id, actor: user)
  rescue
    _ -> []
  end

  defp reload_order(order, org, user) do
    Ash.get!(Order, order.id, tenant: org.id, actor: user)
    |> Ash.load!(:order_items, tenant: org.id, actor: user)
  rescue
    _ -> order
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

  defp parse_money(existing_money, price_str) do
    currency = if existing_money, do: existing_money.currency, else: :USD

    case Decimal.parse(price_str || "") do
      {d, ""} -> Money.new!(currency, d)
      _ -> existing_money
    end
  end

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
