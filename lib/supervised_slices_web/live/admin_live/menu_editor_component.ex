defmodule SupervisedSlicesWeb.AdminLive.MenuEditorComponent do
  use SupervisedSlicesWeb, :live_component

  alias SupervisedSlices.Menu.{
    Category,
    MenuItem,
    MenuItemImage,
    MenuItemSize,
    MenuItemModifierGroup,
    MenuItemModifier,
    MenuItemModifierGroupLink,
    MenuItemModifierSizePrice,
    MenuImageUploader,
    MenuUpload
  }

  alias SupervisedSlices.Billing

  require Ash.Query

  def mount(socket) do
    {:ok,
     socket
     |> assign(:editing_item_id, nil)
     |> assign(:creating_category, false)
     |> assign(:open_item_id, nil)
     |> assign(:open_item_category_id, nil)
     |> assign(:show_delete_confirm, false)
     |> assign(:open_group_id, nil)
     |> assign(:show_group_delete_confirm, false)
     |> assign(:editing_modifier_id, nil)
     |> assign(:adding_modifier, false)
     |> assign(:current_upload, nil)
     |> assign(:has_completed_upload, false)
     |> assign(:purchasing_upload, false)
     |> allow_upload(:item_image,
       accept: ~w(.jpg .jpeg .png .webp .gif),
       max_entries: 5,
       max_file_size: 8_000_000
     )
     |> allow_upload(:menu_file,
       accept: ~w(.jpg .jpeg .png .webp .pdf),
       max_entries: 1,
       max_file_size: 20_000_000
     )}
  end

  def update(%{open_group_id: id} = _assigns, socket) when not is_nil(id) do
    {:ok, assign(socket, open_group_id: id, show_group_delete_confirm: false)}
  end

  def update(%{reload_modifier_groups: _, reload_categories: _} = _assigns, socket) do
    scope = socket.assigns.ash_scope

    {:ok,
     socket
     |> assign(:modifier_groups, load_modifier_groups(scope))
     |> assign(:categories, load_categories(scope))}
  end

  def update(%{reload_modifier_groups: true} = _assigns, socket) do
    scope = socket.assigns.ash_scope
    {:ok, assign(socket, :modifier_groups, load_modifier_groups(scope))}
  end

  def update(%{reload_categories: true} = _assigns, socket) do
    scope = socket.assigns.ash_scope
    {:ok, assign(socket, :categories, load_categories(scope))}
  end

  def update(%{ash_scope: scope, org: org} = assigns, socket) do
    current_upload =
      MenuUpload
      |> Ash.Query.filter(organization_id == ^org.id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read_one!(authorize?: false)

    has_completed_upload =
      MenuUpload
      |> Ash.Query.filter(organization_id == ^org.id and status == :completed)
      |> Ash.Query.limit(1)
      |> Ash.read_one!(authorize?: false)
      |> case do
        nil -> false
        _ -> true
      end

    socket =
      socket
      |> assign(:ash_scope, scope)
      |> assign(:org, org)
      |> assign(:current_upload, current_upload)
      |> assign(:has_completed_upload, has_completed_upload)
      |> assign_new(:categories, fn -> load_categories(scope) end)
      |> assign_new(:modifier_groups, fn -> load_modifier_groups(scope) end)

    {:ok, assign(socket, Map.drop(assigns, [:ash_scope, :org]))}
  end

  # ---------------------------------------------------------------------------
  # Item events
  # ---------------------------------------------------------------------------

  def handle_event("edit_item", %{"id" => id}, socket) do
    {:noreply, assign(socket, open_item_id: id, show_delete_confirm: false)}
  end

  def handle_event("add_item", %{"category_id" => id}, socket) do
    {:noreply,
     assign(socket, open_item_id: :new, open_item_category_id: id, show_delete_confirm: false)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     assign(socket,
       editing_item_id: nil,
       open_item_id: nil,
       open_item_category_id: nil,
       show_delete_confirm: false
     )}
  end

  def handle_event("delete_item", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, true)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, false)}
  end

  def handle_event("confirm_delete_item", _params, socket) do
    %{ash_scope: scope, open_item_id: item_id} = socket.assigns
    item = MenuItem.get!(item_id, scope: scope)
    MenuItem.destroy!(item, scope: scope)
    categories = load_categories(scope)

    {:noreply,
     assign(socket,
       categories: categories,
       open_item_id: nil,
       open_item_category_id: nil,
       show_delete_confirm: false
     )}
  end

  def handle_event("save_item", %{"item" => params}, socket) do
    %{ash_scope: scope} = socket.assigns

    uploaded_urls =
      consume_uploaded_entries(socket, :item_image, fn %{path: path}, entry ->
        {:ok, MenuImageUploader.upload(scope.current_tenant, path, entry.client_type)}
      end)

    item = MenuItem.get!(params["id"], scope: scope, load: [:images])

    next_position = length(item.images)

    uploaded_urls
    |> Enum.with_index(next_position)
    |> Enum.each(fn {url, pos} ->
      MenuItemImage.create!(%{url: url, position: pos, menu_item_id: item.id}, scope: scope)
    end)

    image_url =
      cond do
        item.images != [] or uploaded_urls != [] -> item.image_url
        params["image_url"] != "" -> params["image_url"]
        true -> item.image_url
      end

    attrs = %{
      name: params["name"],
      description: params["description"],
      price: parse_money(params["price"]),
      image_url: image_url,
      sort_order: String.to_integer(params["sort_order"] || "0")
    }

    MenuItem.update!(item, attrs, scope: scope)

    categories = load_categories(scope)

    {:noreply,
     assign(socket,
       categories: categories,
       open_item_id: nil,
       open_item_category_id: nil,
       show_delete_confirm: false
     )}
  end

  def handle_event("delete_image", %{"id" => id}, socket) do
    %{ash_scope: scope} = socket.assigns
    MenuItemImage.destroy!(id, scope: scope)
    categories = load_categories(scope)
    {:noreply, assign(socket, :categories, categories)}
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

    uploaded_urls =
      consume_uploaded_entries(socket, :item_image, fn %{path: path}, entry ->
        {:ok, MenuImageUploader.upload(scope.current_tenant, path, entry.client_type)}
      end)

    item =
      MenuItem.create!(
        %{
          name: params["name"],
          description: params["description"],
          price: parse_money(params["price"]),
          image_url: if(uploaded_urls == [], do: params["image_url"], else: nil),
          sort_order: String.to_integer(params["sort_order"] || "0"),
          category_id: params["category_id"]
        },
        scope: scope
      )

    uploaded_urls
    |> Enum.with_index()
    |> Enum.each(fn {url, pos} ->
      MenuItemImage.create!(%{url: url, position: pos, menu_item_id: item.id}, scope: scope)
    end)

    categories = load_categories(scope)

    {:noreply,
     assign(socket,
       categories: categories,
       open_item_id: item.id,
       open_item_category_id: nil,
       show_delete_confirm: false
     )}
  end

  # ---------------------------------------------------------------------------
  # Category events
  # ---------------------------------------------------------------------------

  def handle_event("edit_category", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_item_id: "cat:#{id}")}
  end

  def handle_event("add_category", _params, socket) do
    {:noreply, assign(socket, creating_category: true, editing_item_id: nil)}
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

  def handle_event("move_category", %{"id" => id, "direction" => direction}, socket) do
    %{ash_scope: scope, categories: categories} = socket.assigns
    direction = String.to_existing_atom(direction)

    index = Enum.find_index(categories, &(&1.id == id))

    if index do
      case direction do
        :up when index > 0 ->
          prev = Enum.at(categories, index - 1)
          curr = Enum.at(categories, index)
          swap_sort_orders(Category, curr, prev, scope)

        :down when index < length(categories) - 1 ->
          next = Enum.at(categories, index + 1)
          curr = Enum.at(categories, index)
          swap_sort_orders(Category, curr, next, scope)

        _ ->
          :ok
      end
    end

    {:noreply, assign(socket, categories: load_categories(scope))}
  end

  def handle_event("move_item", %{"id" => id, "direction" => direction}, socket) do
    %{ash_scope: scope, categories: categories} = socket.assigns
    direction = String.to_existing_atom(direction)

    found =
      Enum.find_value(categories, fn cat ->
        idx = Enum.find_index(cat.menu_items, &(&1.id == id))
        if idx, do: {cat, idx}
      end)

    if found do
      {category, index} = found
      items = category.menu_items

      case direction do
        :up when index > 0 ->
          prev = Enum.at(items, index - 1)
          curr = Enum.at(items, index)
          swap_sort_orders(MenuItem, curr, prev, scope)

        :down when index < length(items) - 1 ->
          next = Enum.at(items, index + 1)
          curr = Enum.at(items, index)
          swap_sort_orders(MenuItem, curr, next, scope)

        _ ->
          :ok
      end
    end

    {:noreply, assign(socket, categories: load_categories(scope))}
  end

  # ---------------------------------------------------------------------------
  # Size events
  # ---------------------------------------------------------------------------

  def handle_event("create_size", %{"size" => params}, socket) do
    %{ash_scope: scope} = socket.assigns

    MenuItemSize.create!(
      %{
        name: params["name"],
        price: Money.new!(:CAD, Decimal.new(params["price"] || "0")),
        menu_item_id: params["menu_item_id"]
      },
      scope: scope
    )

    MenuItem.get!(params["menu_item_id"], scope: scope)
    |> MenuItem.update!(%{price: nil}, scope: scope)

    categories = load_categories(scope)
    {:noreply, assign(socket, :categories, categories)}
  end

  def handle_event("delete_size", %{"id" => id}, socket) do
    %{ash_scope: scope} = socket.assigns
    MenuItemSize.get!(id, scope: scope) |> MenuItemSize.destroy!(scope: scope)
    categories = load_categories(scope)
    {:noreply, assign(socket, :categories, categories)}
  end

  # ---------------------------------------------------------------------------
  # Modifier group events
  # ---------------------------------------------------------------------------

  def handle_event("add_modifier_group", _params, socket) do
    {:noreply, assign(socket, open_group_id: :new, show_group_delete_confirm: false)}
  end

  def handle_event("cancel_group_edit", _params, socket) do
    {:noreply,
     assign(socket,
       open_group_id: nil,
       show_group_delete_confirm: false,
       editing_modifier_id: nil,
       adding_modifier: false
     )}
  end

  def handle_event("create_modifier_group", %{"group" => params}, socket) do
    %{ash_scope: scope} = socket.assigns

    group =
      MenuItemModifierGroup.create!(
        %{
          name: params["name"],
          required: Map.get(params, "required") == "true",
          min_selections: parse_int(params["min_selections"]),
          max_selections: parse_int(params["max_selections"]),
          sort_order: parse_int(params["sort_order"]) || 0
        },
        scope: scope
      )

    modifier_groups = load_modifier_groups(scope)

    {:noreply,
     assign(socket, modifier_groups: modifier_groups, open_group_id: group.id, adding_modifier: false)}
  end

  def handle_event("save_group", %{"group" => params}, socket) do
    %{ash_scope: scope, open_group_id: group_id} = socket.assigns

    group = MenuItemModifierGroup.get!(group_id, scope: scope)

    MenuItemModifierGroup.update!(
      group,
      %{
        name: params["name"],
        required: Map.get(params, "required") == "true",
        min_selections: parse_int(params["min_selections"]),
        max_selections: parse_int(params["max_selections"]),
        sort_order: parse_int(params["sort_order"]) || group.sort_order
      },
      scope: scope
    )

    modifier_groups = load_modifier_groups(scope)
    categories = load_categories(scope)

    {:noreply, assign(socket, modifier_groups: modifier_groups, categories: categories)}
  end

  def handle_event("delete_group", _params, socket) do
    {:noreply, assign(socket, show_group_delete_confirm: true)}
  end

  def handle_event("cancel_delete_group", _params, socket) do
    {:noreply, assign(socket, show_group_delete_confirm: false)}
  end

  def handle_event("confirm_delete_group", _params, socket) do
    %{ash_scope: scope, open_group_id: group_id} = socket.assigns

    group = MenuItemModifierGroup.get!(group_id, scope: scope, load: :modifiers)
    Enum.each(group.modifiers, &MenuItemModifier.destroy!(&1, scope: scope))
    MenuItemModifierGroup.destroy!(group, scope: scope)

    modifier_groups = load_modifier_groups(scope)
    categories = load_categories(scope)

    {:noreply,
     assign(socket,
       modifier_groups: modifier_groups,
       categories: categories,
       open_group_id: nil,
       show_group_delete_confirm: false
     )}
  end

  def handle_event("add_modifier", _params, socket) do
    {:noreply, assign(socket, adding_modifier: true, editing_modifier_id: nil)}
  end

  def handle_event("cancel_add_modifier", _params, socket) do
    {:noreply, assign(socket, adding_modifier: false)}
  end

  def handle_event("create_modifier", %{"modifier" => params}, socket) do
    %{ash_scope: scope, open_group_id: group_id} = socket.assigns

    MenuItemModifier.create!(
      %{
        name: params["name"],
        price_delta: parse_money(params["price_delta"]),
        modifier_group_id: group_id
      },
      scope: scope
    )

    modifier_groups = load_modifier_groups(scope)

    {:noreply, assign(socket, modifier_groups: modifier_groups, adding_modifier: false)}
  end

  def handle_event("edit_modifier", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_modifier_id: id, adding_modifier: false)}
  end

  def handle_event("cancel_edit_modifier", _params, socket) do
    {:noreply, assign(socket, editing_modifier_id: nil)}
  end

  def handle_event("save_modifier", %{"modifier" => params}, socket) do
    %{ash_scope: scope} = socket.assigns

    modifier = MenuItemModifier.get!(params["id"], scope: scope)

    MenuItemModifier.update!(
      modifier,
      %{
        name: params["name"],
        price_delta: parse_money(params["price_delta"]),
        sort_order: parse_int(params["sort_order"]) || modifier.sort_order,
        available: Map.get(params, "available") == "true"
      },
      scope: scope
    )

    modifier_groups = load_modifier_groups(scope)

    {:noreply, assign(socket, modifier_groups: modifier_groups, editing_modifier_id: nil)}
  end

  def handle_event("delete_modifier", %{"id" => id}, socket) do
    %{ash_scope: scope} = socket.assigns
    MenuItemModifier.get!(id, scope: scope) |> MenuItemModifier.destroy!(scope: scope)
    modifier_groups = load_modifier_groups(scope)
    {:noreply, assign(socket, modifier_groups: modifier_groups)}
  end

  def handle_event("toggle_modifier_available", %{"id" => id}, socket) do
    %{ash_scope: scope} = socket.assigns
    modifier = MenuItemModifier.get!(id, scope: scope)
    MenuItemModifier.update!(modifier, %{available: !modifier.available}, scope: scope)
    modifier_groups = load_modifier_groups(scope)
    {:noreply, assign(socket, modifier_groups: modifier_groups)}
  end

  def handle_event(
        "save_modifier_size_price",
        %{"modifier_id" => mod_id, "size_id" => size_id, "value" => price_str},
        socket
      ) do
    %{ash_scope: scope} = socket.assigns

    case parse_money(price_str) do
      nil ->
        existing =
          MenuItemModifierSizePrice
          |> Ash.Query.filter(modifier_id == ^mod_id and size_id == ^size_id)
          |> Ash.read_one!(scope: scope, authorize?: false)

        if existing, do: MenuItemModifierSizePrice.destroy!(existing, scope: scope)

      money ->
        MenuItemModifierSizePrice.upsert!(
          %{modifier_id: mod_id, size_id: size_id, price_delta: money},
          scope: scope
        )
    end

    categories = load_categories(scope)
    {:noreply, assign(socket, categories: categories)}
  end

  # ---------------------------------------------------------------------------
  # Item <-> Modifier group assignment
  # ---------------------------------------------------------------------------

  def handle_event(
        "assign_modifier_group",
        %{"item_id" => item_id, "group_id" => group_id},
        socket
      ) do
    %{ash_scope: scope} = socket.assigns

    MenuItemModifierGroupLink.assign!(
      %{menu_item_id: item_id, modifier_group_id: group_id},
      scope: scope
    )

    categories = load_categories(scope)
    {:noreply, assign(socket, categories: categories)}
  end

  def handle_event(
        "remove_item_modifier_group",
        %{"item_id" => item_id, "group_id" => group_id},
        socket
      ) do
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
  # Upsell events
  # ---------------------------------------------------------------------------

  def handle_event("toggle_upsell", %{"id" => id}, socket) do
    %{ash_scope: scope} = socket.assigns
    item = MenuItem.get!(id, scope: scope)
    MenuItem.update!(item, %{is_upsell: !item.is_upsell}, scope: scope)
    {:noreply, assign(socket, :categories, load_categories(scope))}
  end

  def handle_event("purchase_menu_upload", _params, socket) do
    %{org: org} = socket.assigns
    socket = assign(socket, :purchasing_upload, true)

    price_id = Application.get_env(:supervised_slices, :stripe)[:price_id_menu_upload]
    base_url = SupervisedSlicesWeb.Endpoint.url()
    success_url = base_url <> ~p"/billing/success/#{org.slug}"
    cancel_url = base_url <> ~p"/kitchen/#{org.slug}/menu"

    metadata = %{"menu_upload" => "true", "org_id" => org.id}

    with {:ok, customer_id} <- get_stripe_customer_id(org),
         {:ok, session} <-
           Billing.create_one_time_checkout_session(
             customer_id,
             price_id,
             metadata,
             success_url,
             cancel_url
           ) do
      {:noreply, redirect(socket, external: session.url)}
    else
      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:purchasing_upload, false)
         |> put_flash(:error, "Could not start checkout. Please try again.")}
    end
  end

  def handle_event("validate_menu_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload_menu", _params, socket) do
    %{org: org} = socket.assigns

    uploaded_file_names =
      consume_uploaded_entries(socket, :menu_file, fn %{path: path}, entry ->
        {:ok, MenuImageUploader.upload(org.id, path, entry.client_type)}
      end)

    case uploaded_file_names do
      [file_name] ->
        case MenuUpload.create(%{file_url: file_name, organization_id: org.id}, authorize?: false)
             |> dbg do
          {:ok, upload} ->
            {:noreply,
             socket
             |> put_flash(:info, "Menu upload started. It will be processed shortly.")
             |> assign(:current_upload, upload)}

          {:error, error} ->
            dbg(error)
            {:noreply, put_flash(socket, :error, "Failed to start upload: #{inspect(error)}")}
        end

      [] ->
        {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    assigns =
      assigns
      |> assign(:open_item, resolve_open_item(assigns.open_item_id, assigns.categories))
      |> assign(:open_group, resolve_open_group(assigns.open_group_id, assigns.modifier_groups))

    ~H"""
    <div>
      <div class="flex flex-col lg:flex-row gap-12 items-start">
        <div class="flex-1 space-y-12 w-full">
          <div
            :if={not @org.menu_upload_purchased}
            class="bg-surface-container-low p-6 rounded-xl border-2 border-dashed border-outline-variant/50"
          >
            <div class="flex items-center justify-between">
              <div>
                <h3 class="text-lg font-black text-on-surface font-headline uppercase tracking-tight">
                  AI Menu Importer
                </h3>
                <p class="text-sm text-on-surface-variant mt-1">
                  Upload a photo of your menu and let our AI build your entire digital catalog — categories, items, sizes, and modifiers.
                </p>
              </div>
              <div class="flex items-center gap-4 ml-8 shrink-0">
                <span class="text-sm font-black text-on-surface-variant">$150 one-time</span>
                <button
                  phx-click="purchase_menu_upload"
                  phx-target={@myself}
                  disabled={@purchasing_upload}
                  class="bg-primary text-white px-6 py-2.5 rounded-md font-bold text-sm uppercase tracking-wide transition-all active:scale-95 shadow-sm inline-flex items-center gap-2 disabled:opacity-60"
                >
                  <span :if={not @purchasing_upload} class="material-symbols-outlined text-lg">
                    auto_awesome
                  </span>
                  <span
                    :if={@purchasing_upload}
                    class="material-symbols-outlined text-lg animate-spin"
                  >
                    refresh
                  </span>
                  {if @purchasing_upload, do: "Processing...", else: "Purchase"}
                </button>
              </div>
            </div>
          </div>

          <div
            :if={@org.menu_upload_purchased and not @has_completed_upload}
            class="bg-surface-container-low p-6 rounded-xl border-2 border-dashed border-primary/30 mb-8"
          >
            <div class="flex items-center justify-between mb-4">
              <div>
                <h3 class="text-lg font-black text-on-surface font-headline uppercase tracking-tight">
                  AI Menu Importer
                </h3>
                <p class="text-sm text-on-surface-variant">
                  Upload your menu (JPG, PNG, WebP, or PDF) and we'll build your menu automatically.
                </p>
              </div>
              <div class="flex items-center gap-4">
                <form phx-submit="upload_menu" phx-change="validate_menu_upload" phx-target={@myself}>
                  <.live_file_input upload={@uploads.menu_file} class="hidden" />
                  <label
                    for={@uploads.menu_file.ref}
                    class="cursor-pointer bg-primary text-white px-6 py-2.5 rounded-md font-bold text-sm uppercase tracking-wide transition-all active:scale-95 shadow-sm inline-flex items-center gap-2"
                  >
                    <span class="material-symbols-outlined text-lg">upload_file</span> Choose File
                  </label>
                  <button
                    :if={@uploads.menu_file.entries != []}
                    type="submit"
                    class="ml-4 bg-secondary text-white px-6 py-2.5 rounded-md font-bold text-sm uppercase tracking-wide transition-all active:scale-95 shadow-sm"
                  >
                    Start Import
                  </button>
                </form>
              </div>
            </div>

            <div
              :for={entry <- @uploads.menu_file.entries}
              class="mt-4 flex items-center gap-4 text-sm text-on-surface-variant"
            >
              <span class="font-bold">{entry.client_name}</span>
              <div class="flex-1 h-2 bg-surface-container-highest rounded-full overflow-hidden">
                <div class="h-full bg-primary transition-all" style={"width: #{entry.progress}%"}>
                </div>
              </div>
              <span>{entry.progress}%</span>
            </div>

            <div
              :if={@current_upload}
              class="mt-4 p-4 bg-surface-container rounded-lg flex items-center gap-4"
            >
              <div
                :if={@current_upload.status == :pending or @current_upload.status == :processing}
                class="animate-pulse flex items-center gap-2 text-primary font-bold"
              >
                <span class="material-symbols-outlined animate-spin">refresh</span>
                Processing your menu... This may take a minute.
              </div>
              <div
                :if={@current_upload.status == :completed}
                class="text-secondary font-bold flex items-center gap-2"
              >
                <span class="material-symbols-outlined">check_circle</span>
                Import completed successfully!
              </div>
              <div
                :if={@current_upload.status == :failed}
                class="text-error font-bold flex items-center gap-2"
              >
                <span class="material-symbols-outlined">error</span>
                Import failed: {@current_upload.error_message}
              </div>
            </div>
          </div>

          <div class="flex items-center justify-between">
            <div>
              <h2 class="font-headline text-2xl font-black text-on-surface">
                Menu Items
              </h2>
              <p class="text-sm text-on-surface-variant mt-1">
                Manage your menu items and customization options
              </p>
            </div>
            <button
              phx-click="add_category"
              phx-target={@myself}
              class="flex items-center gap-2 bg-primary text-white px-6 py-2.5 rounded-md font-bold text-sm uppercase tracking-wide transition-all active:scale-95 shadow-sm"
            >
              <span class="material-symbols-outlined text-lg">add</span> New Category
            </button>
          </div>

          <form
            :if={@creating_category}
            phx-submit="create_category"
            phx-target={@myself}
            class="flex items-center gap-4 bg-surface-container-low p-4 rounded-md"
          >
            <input
              type="text"
              name="category[name]"
              required
              autofocus
              placeholder="e.g. Starters"
              class="flex-1 text-lg font-black bg-surface-container-highest border-0 rounded px-4 py-2 focus:ring-1 focus:ring-primary outline-none"
            />
            <input
              type="number"
              name="category[sort_order]"
              placeholder="Order"
              class="w-20 bg-surface-container-highest border-0 rounded px-3 py-2 text-sm focus:ring-1 focus:ring-primary outline-none"
            />
            <button
              type="submit"
              class="bg-primary text-white px-5 py-2 rounded-md text-sm font-bold uppercase tracking-wide phx-submit-loading:opacity-70 phx-submit-loading:cursor-wait"
            >
              <span class="phx-submit-loading:!hidden">Save</span>
              <span class="hidden phx-submit-loading:!flex items-center justify-center">
                <.icon name="hero-arrow-path" class="size-4 animate-spin" />
              </span>
            </button>
            <button
              type="button"
              phx-click="cancel_add_category"
              phx-target={@myself}
              class="text-on-surface-variant hover:text-on-surface px-3 py-2"
            >
              <span class="material-symbols-outlined text-xl">close</span>
            </button>
          </form>

          <%= if Enum.empty?(@categories) do %>
            <div class="flex flex-col items-center py-24 text-on-surface-variant/20">
              <span class="material-symbols-outlined text-8xl">restaurant_menu</span>
              <p class="mt-4 text-xl font-black font-headline uppercase tracking-widest opacity-40">
                No categories yet
              </p>
            </div>
          <% end %>

          <%= for category <- @categories do %>
            <div class="space-y-4">
              <%= if @editing_item_id == "cat:#{category.id}" do %>
                <form
                  phx-submit="save_category"
                  phx-target={@myself}
                  class="flex items-center gap-4 bg-surface-container-low p-4 rounded-md"
                >
                  <input type="hidden" name="category[id]" value={category.id} />
                  <input
                    type="text"
                    name="category[name]"
                    value={category.name}
                    class="flex-1 text-lg font-black bg-surface-container-highest border-0 rounded px-4 py-2 focus:ring-1 focus:ring-primary outline-none"
                    autofocus
                  />
                  <input
                    type="number"
                    name="category[sort_order]"
                    value={category.sort_order}
                    class="w-20 bg-surface-container-highest border-0 rounded px-3 py-2 text-sm focus:ring-1 focus:ring-primary outline-none"
                    placeholder="Order"
                  />
                  <button
                    type="submit"
                    class="bg-primary text-white px-5 py-2 rounded-md text-sm font-bold uppercase tracking-wide phx-submit-loading:opacity-70 phx-submit-loading:cursor-wait"
                  >
                    <span class="phx-submit-loading:!hidden">Save</span>
                    <span class="hidden phx-submit-loading:!flex items-center justify-center">
                      <.icon name="hero-arrow-path" class="size-4 animate-spin" />
                    </span>
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_edit"
                    phx-target={@myself}
                    class="text-on-surface-variant hover:text-on-surface px-3 py-2"
                  >
                    <span class="material-symbols-outlined text-xl">close</span>
                  </button>
                </form>
              <% else %>
                <div class="flex items-center gap-2 group">
                  <h3 class="text-2xl font-black text-on-surface flex-1 font-headline tracking-tight">
                    {category.name}
                  </h3>
                  <div class="opacity-0 group-hover:opacity-100 flex items-center gap-1 transition-all">
                    <button
                      phx-click="move_category"
                      phx-value-id={category.id}
                      phx-value-direction="up"
                      phx-target={@myself}
                      class="text-on-surface-variant/40 hover:text-primary p-1 phx-click-loading:opacity-50 phx-click-loading:cursor-wait"
                      title="Move up"
                    >
                      <span class="material-symbols-outlined text-lg phx-click-loading:animate-spin">
                        arrow_upward
                      </span>
                    </button>
                    <button
                      phx-click="move_category"
                      phx-value-id={category.id}
                      phx-value-direction="down"
                      phx-target={@myself}
                      class="text-on-surface-variant/40 hover:text-primary p-1 phx-click-loading:opacity-50 phx-click-loading:cursor-wait"
                      title="Move down"
                    >
                      <span class="material-symbols-outlined text-lg phx-click-loading:animate-spin">
                        arrow_downward
                      </span>
                    </button>
                    <button
                      phx-click="edit_category"
                      phx-value-id={category.id}
                      phx-target={@myself}
                      class="text-on-surface-variant/40 hover:text-primary p-1"
                      title="Edit category"
                    >
                      <span class="material-symbols-outlined text-lg">edit</span>
                    </button>
                  </div>
                </div>
              <% end %>

              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
                <div
                  :for={item <- category.menu_items}
                  class={[
                    "bg-surface-container-low rounded-md flex flex-col shadow-sm overflow-hidden transition-all duration-300 group",
                    if(not item.available, do: "opacity-50 grayscale")
                  ]}
                >
                  <div class="aspect-square relative overflow-hidden bg-surface-container-high">
                    <%= if item.image_url do %>
                      <img
                        src={item.image_url}
                        alt={item.name}
                        class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
                      />
                    <% else %>
                      <div class="w-full h-full flex items-center justify-center text-on-surface-variant/20">
                        <span class="material-symbols-outlined text-4xl">image</span>
                      </div>
                    <% end %>
                    <div class="absolute top-3 right-3 flex gap-2">
                      <button
                        phx-click="toggle_available"
                        phx-value-id={item.id}
                        phx-target={@myself}
                        class={[
                          "px-2 py-1 rounded text-[10px] font-black uppercase tracking-widest shadow-lg backdrop-blur-md phx-click-loading:opacity-50 phx-click-loading:cursor-wait",
                          if(item.available,
                            do: "bg-secondary-container/90 text-on-secondary-container",
                            else: "bg-surface-container-highest/90 text-on-surface-variant"
                          )
                        ]}
                      >
                        <span class="phx-click-loading:!hidden">
                          {if item.available, do: "LIVE", else: "OFF"}
                        </span>
                        <span class="hidden phx-click-loading:!flex items-center justify-center">
                          <.icon name="hero-arrow-path" class="size-3 animate-spin" />
                        </span>
                      </button>
                    </div>
                  </div>

                  <div class="p-5 flex-1 flex flex-col">
                    <div class="flex justify-between items-start gap-2 mb-2">
                      <h4 class="font-bold text-on-surface text-sm leading-tight group-hover:text-primary transition-colors">
                        {item.name}
                      </h4>
                      <span class="text-sm font-black text-primary shrink-0">
                        <%= cond do %>
                          <% item.price -> %>
                            {format_money(item.price)}
                          <% not Enum.empty?(item.sizes || []) -> %>
                            From {item.sizes
                            |> Enum.min_by(& &1.price.amount)
                            |> then(& &1.price)
                            |> format_money()}
                          <% true -> %>
                            —
                        <% end %>
                      </span>
                    </div>
                    <p class="text-xs text-on-surface-variant/60 line-clamp-2 mb-4 leading-relaxed italic">
                      {item.description}
                    </p>

                    <div class="mt-auto flex items-center justify-between gap-4 pt-4 border-t border-on-surface/5">
                      <div class="flex gap-1.5 overflow-hidden">
                        <%= if not Enum.empty?(item.sizes || []) do %>
                          <span class="bg-surface-container-highest text-[9px] font-black uppercase tracking-widest px-2 py-0.5 rounded text-on-surface-variant">
                            {length(item.sizes)} SIZES
                          </span>
                        <% end %>
                        <%= if not Enum.empty?(item.modifier_groups || []) do %>
                          <span class="bg-surface-container-highest text-[9px] font-black uppercase tracking-widest px-2 py-0.5 rounded text-on-surface-variant">
                            {length(item.modifier_groups)} MODS
                          </span>
                        <% end %>
                        <%= if item.is_upsell do %>
                          <span class="bg-surface-container-highest text-[9px] font-black uppercase tracking-widest px-2 py-0.5 rounded text-on-surface-variant">
                            UPSELL
                          </span>
                        <% end %>
                      </div>
                      <div class="flex items-center gap-1">
                        <button
                          phx-click="move_item"
                          phx-value-id={item.id}
                          phx-value-direction="up"
                          phx-target={@myself}
                          class="text-on-surface-variant/40 hover:text-primary transition-colors p-1 phx-click-loading:opacity-50 phx-click-loading:cursor-wait"
                          title="Move up"
                        >
                          <span class="material-symbols-outlined text-lg phx-click-loading:animate-spin">
                            arrow_upward
                          </span>
                        </button>
                        <button
                          phx-click="move_item"
                          phx-value-id={item.id}
                          phx-value-direction="down"
                          phx-target={@myself}
                          class="text-on-surface-variant/40 hover:text-primary transition-colors p-1 phx-click-loading:opacity-50 phx-click-loading:cursor-wait"
                          title="Move down"
                        >
                          <span class="material-symbols-outlined text-lg phx-click-loading:animate-spin">
                            arrow_downward
                          </span>
                        </button>
                        <button
                          phx-click="edit_item"
                          phx-value-id={item.id}
                          phx-target={@myself}
                          class="text-on-surface-variant/40 hover:text-primary transition-colors p-1"
                          title="Edit item"
                        >
                          <span class="material-symbols-outlined text-lg">edit</span>
                        </button>
                      </div>
                    </div>
                  </div>
                </div>

                <button
                  phx-click="add_item"
                  phx-value-category_id={category.id}
                  phx-target={@myself}
                  class="flex flex-col items-center justify-center gap-3 p-8 rounded-md border-2 border-dashed border-on-surface/5 hover:border-primary/20 hover:bg-surface-container-low transition-all group"
                >
                  <span class="material-symbols-outlined text-primary/40 group-hover:text-primary transition-colors text-3xl">
                    add_circle
                  </span>
                  <span class="text-[10px] font-black text-on-surface-variant uppercase tracking-[0.2em]">
                    Add item to {category.name}
                  </span>
                </button>
              </div>
            </div>
          <% end %>
        </div>

        <aside class="w-full lg:w-80 shrink-0 space-y-6">
          <div class="bg-surface-container-low rounded-md p-6 space-y-4">
            <div class="flex items-center justify-between">
              <p class="text-[0.65rem] font-black text-on-surface-variant uppercase tracking-[0.2em]">
                Modifier Groups
              </p>
              <button
                phx-click="add_modifier_group"
                phx-target={@myself}
                type="button"
                class="flex items-center gap-1.5 text-[0.65rem] text-primary hover:opacity-80 font-black uppercase tracking-widest"
              >
                <span class="material-symbols-outlined text-sm">add_circle</span> New Group
              </button>
            </div>

            <p :if={Enum.empty?(@modifier_groups)} class="text-xs text-on-surface-variant italic">
              No modifier groups yet.
            </p>

            <div :if={not Enum.empty?(@modifier_groups)} class="space-y-1">
              <.live_component
                :for={group <- @modifier_groups}
                module={SupervisedSlicesWeb.AdminLive.ModifierGroupRowComponent}
                id={"modifier-group-#{group.id}"}
                group={group}
                ash_scope={@ash_scope}
              />
            </div>
          </div>
        </aside>
      </div>

      <.menu_item_drawer
        item={@open_item}
        open_item_id={@open_item_id}
        category_id={@open_item_category_id}
        modifier_groups={@modifier_groups}
        show_delete_confirm={@show_delete_confirm}
        myself={@myself}
        uploads={@uploads}
      />

      <.modifier_group_drawer
        group={@open_group}
        open_group_id={@open_group_id}
        show_group_delete_confirm={@show_group_delete_confirm}
        editing_modifier_id={@editing_modifier_id}
        adding_modifier={@adding_modifier}
        myself={@myself}
      />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp get_stripe_customer_id(%{stripe_customer_id: id}) when is_binary(id) and id != "",
    do: {:ok, id}

  defp get_stripe_customer_id(_org), do: {:error, :no_stripe_customer}

  defp load_categories(scope) do
    Category.active!(
      scope: scope,
      load: [
        menu_items:
          MenuItem
          |> Ash.Query.sort(sort_order: :asc)
          |> Ash.Query.load(
            modifier_groups: [modifiers: [:size_prices]],
            sizes: MenuItemSize |> Ash.Query.sort(sort_order: :asc),
            images: []
          )
      ]
    )
  end

  defp load_modifier_groups(scope) do
    MenuItemModifierGroup.list!(scope: scope, load: [:modifiers], authorize?: false)
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_money(nil), do: nil
  defp parse_money(""), do: nil

  defp parse_money(str) do
    case Decimal.parse(str) do
      {d, ""} -> Money.new!(:CAD, d)
      _ -> nil
    end
  end

  defp format_money(money) do
    Money.to_string!(money)
  rescue
    _ -> "#{money}"
  end

  defp swap_sort_orders(resource, a, b, scope) do
    a_sort = a.sort_order
    b_sort = b.sort_order

    {a_sort, b_sort} = if a_sort == b_sort, do: {a_sort, a_sort + 1}, else: {a_sort, b_sort}

    resource.update!(a, %{sort_order: b_sort}, scope: scope)
    resource.update!(b, %{sort_order: a_sort}, scope: scope)
  end

  defp money_amount(nil), do: "0.00"
  defp money_amount(money), do: Decimal.to_string(money.amount, :normal)

  defp resolve_open_item(nil, _categories), do: nil
  defp resolve_open_item(:new, _categories), do: :new

  defp resolve_open_item(id, categories) do
    categories
    |> Enum.flat_map(& &1.menu_items)
    |> Enum.find(&(to_string(&1.id) == to_string(id)))
  end

  defp resolve_open_group(nil, _groups), do: nil
  defp resolve_open_group(:new, _groups), do: :new

  defp resolve_open_group(id, groups) do
    Enum.find(groups, &(to_string(&1.id) == to_string(id)))
  end

  # ---------------------------------------------------------------------------
  # Menu Item Drawer (functional component)
  # ---------------------------------------------------------------------------

  attr :item, :any, default: nil
  attr :open_item_id, :any, default: nil
  attr :category_id, :string, default: nil
  attr :modifier_groups, :list, default: []
  attr :show_delete_confirm, :boolean, default: false
  attr :myself, :any, required: true
  attr :uploads, :any, required: true

  defp menu_item_drawer(assigns) do
    ~H"""
    <div
      id="item-drawer-wrapper"
      class={[
        "fixed inset-0 z-40 transition-all duration-300",
        if(@open_item_id, do: "visible", else: "invisible pointer-events-none")
      ]}
    >
      <div
        class={[
          "absolute inset-0 bg-black/30 transition-opacity duration-300",
          if(@open_item_id, do: "opacity-100", else: "opacity-0")
        ]}
        phx-click="cancel_edit"
        phx-target={@myself}
      >
      </div>

      <div class={[
        "absolute top-0 right-0 bottom-0 w-full md:w-[640px] bg-background flex flex-col",
        "shadow-[-24px_0px_64px_rgba(0,0,0,0.10)] transition-transform duration-300 ease-out",
        if(@open_item_id, do: "translate-x-0", else: "translate-x-full")
      ]}>
        <div class="flex items-center justify-between px-8 py-6 shrink-0 bg-background/95 backdrop-blur-sm border-b border-on-surface/5">
          <h2 class="font-headline text-2xl font-black text-on-surface tracking-tight">
            {if @item == :new or is_nil(@item), do: "New Item", else: @item.name}
          </h2>
          <button
            phx-click="cancel_edit"
            phx-target={@myself}
            class="w-10 h-10 flex items-center justify-center rounded-full bg-surface-container-low hover:bg-surface-container transition-all"
          >
            <span class="material-symbols-outlined">close</span>
          </button>
        </div>

        <div class="flex-1 overflow-y-auto px-8 py-6 space-y-8">
          <%= if @item == :new do %>
            <form id="item-form" phx-submit="create_item" phx-target={@myself} class="space-y-6">
              <input type="hidden" name="item[category_id]" value={@category_id} />
              <.drawer_core_fields item={nil} uploads={@uploads} myself={@myself} />
            </form>
          <% end %>

          <%= if is_struct(@item) do %>
            <form id="item-form" phx-submit="save_item" phx-target={@myself} class="space-y-6">
              <input type="hidden" name="item[id]" value={@item.id} />
              <.drawer_core_fields item={@item} uploads={@uploads} myself={@myself} />
            </form>

            <details class="group/sizes">
              <summary class="list-none flex items-center justify-between cursor-pointer py-2">
                <span class="text-xs font-black text-on-surface-variant uppercase tracking-wider">
                  Sizes
                  <span :if={not Enum.empty?(@item.sizes || [])} class="ml-1 text-primary">
                    ({length(@item.sizes)})
                  </span>
                </span>
                <span class="material-symbols-outlined text-sm text-on-surface-variant transition-transform group-open/sizes:rotate-180">
                  expand_more
                </span>
              </summary>
              <div class="pt-4 space-y-3">
                <div
                  :for={size <- @item.sizes || []}
                  class="flex items-center gap-3 px-3 py-2 bg-surface-container-low rounded-lg"
                >
                  <span class="flex-1 text-sm text-on-surface">{size.name}</span>
                  <span class="text-sm font-bold text-primary">{format_money(size.price)}</span>
                  <button
                    phx-click="delete_size"
                    phx-value-id={size.id}
                    phx-target={@myself}
                    type="button"
                    class="text-on-surface-variant hover:text-error transition-colors p-1"
                  >
                    <span class="material-symbols-outlined" style="font-size: 14px;">close</span>
                  </button>
                </div>
                <p :if={Enum.empty?(@item.sizes || [])} class="text-xs text-on-surface-variant italic">
                  No sizes yet. Add a size to let customers choose (e.g. Small, Medium, Large).
                </p>
                <form
                  phx-submit="create_size"
                  phx-target={@myself}
                  class="flex flex-wrap items-center gap-2 pt-2"
                >
                  <input type="hidden" name="size[menu_item_id]" value={@item.id} />
                  <input
                    type="text"
                    name="size[name]"
                    placeholder="Name (e.g. Large)"
                    class="flex-[2] min-w-[120px] bg-surface-container-low border-0 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-primary outline-none"
                  />
                  <input
                    type="text"
                    name="size[price]"
                    placeholder="Price"
                    inputmode="decimal"
                    class="flex-1 min-w-[80px] bg-surface-container-low border-0 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-primary outline-none"
                  />
                  <button
                    type="submit"
                    class="bg-primary text-white px-4 py-2 rounded-lg text-sm font-bold phx-submit-loading:opacity-70 phx-submit-loading:cursor-wait"
                  >
                    <span class="phx-submit-loading:!hidden">Add</span>
                    <span class="hidden phx-submit-loading:!flex items-center justify-center">
                      <.icon name="hero-arrow-path" class="size-3 animate-spin" />
                    </span>
                  </button>
                </form>
              </div>
            </details>

            <details class="group/mods">
              <summary class="list-none flex items-center justify-between cursor-pointer py-2">
                <span class="text-xs font-black text-on-surface-variant uppercase tracking-wider">
                  Modifier Groups
                  <span :if={not Enum.empty?(@item.modifier_groups || [])} class="ml-1 text-primary">
                    ({length(@item.modifier_groups)})
                  </span>
                </span>
                <span class="material-symbols-outlined text-sm text-on-surface-variant transition-transform group-open/mods:rotate-180">
                  expand_more
                </span>
              </summary>
              <div class="pt-4 space-y-3">
                <%= for group <- (@item.modifier_groups || []) do %>
                  <div class="bg-surface-container-low rounded-lg overflow-hidden">
                    <div class="flex items-center gap-3 px-3 py-2">
                      <span class="flex-1 text-sm font-semibold text-on-surface">{group.name}</span>
                      <span
                        :if={group.required}
                        class="text-[10px] font-bold uppercase tracking-wider bg-primary-fixed text-on-primary-fixed-variant px-2 py-0.5 rounded-full"
                      >
                        Required
                      </span>
                      <span
                        :if={group.max_selections && group.max_selections < 99}
                        class="text-[10px] font-bold uppercase tracking-wider bg-surface-container text-on-surface-variant px-2 py-0.5 rounded-full"
                      >
                        {if group.max_selections == 1,
                          do: "Pick 1",
                          else: "Max #{group.max_selections}"}
                      </span>
                      <span class="text-xs text-on-surface-variant">
                        {length(group.modifiers || [])} options
                      </span>
                      <button
                        phx-click="remove_item_modifier_group"
                        phx-value-item_id={@item.id}
                        phx-value-group_id={group.id}
                        phx-target={@myself}
                        type="button"
                        class="text-on-surface-variant hover:text-error transition-colors p-1"
                        title="Remove from item"
                      >
                        <span class="material-symbols-outlined" style="font-size: 16px;">
                          link_off
                        </span>
                      </button>
                    </div>

                    <%= if not Enum.empty?(@item.sizes || []) and not Enum.empty?(group.modifiers || []) do %>
                      <div class="border-t border-surface-container px-3 pb-3 pt-2">
                        <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest mb-2">
                          Size pricing overrides
                        </p>
                        <div class="overflow-x-auto">
                          <table class="w-full text-xs">
                            <thead>
                              <tr>
                                <th class="text-left text-[10px] font-bold text-on-surface-variant uppercase tracking-widest pb-1 pr-2">
                                  Option
                                </th>
                                <%= for size <- @item.sizes do %>
                                  <th class="text-left text-[10px] font-bold text-on-surface-variant uppercase tracking-widest pb-1 px-1">
                                    {size.name}
                                  </th>
                                <% end %>
                              </tr>
                            </thead>
                            <tbody>
                              <%= for modifier <- group.modifiers do %>
                                <tr>
                                  <td class="pr-2 py-1 text-on-surface font-medium whitespace-nowrap">
                                    {modifier.name}
                                    <span class="text-on-surface-variant font-normal">
                                      {if modifier.price_delta,
                                        do: " (default +#{format_money(modifier.price_delta)})",
                                        else: " (default free)"}
                                    </span>
                                  </td>
                                  <%= for size <- @item.sizes do %>
                                    <td class="px-1 py-1">
                                      <input
                                        type="text"
                                        inputmode="decimal"
                                        placeholder={
                                          if modifier.price_delta,
                                            do: money_amount(modifier.price_delta),
                                            else: "0.00"
                                        }
                                        value={
                                          modifier.size_prices
                                          |> Enum.find(fn sp ->
                                            to_string(sp.size_id) == to_string(size.id)
                                          end)
                                          |> case do
                                            nil -> nil
                                            sp -> money_amount(sp.price_delta)
                                          end
                                        }
                                        phx-blur="save_modifier_size_price"
                                        phx-value-modifier_id={modifier.id}
                                        phx-value-size_id={size.id}
                                        phx-target={@myself}
                                        class="w-20 bg-surface-container-highest border-0 rounded px-2 py-1 text-xs focus:ring-1 focus:ring-primary outline-none"
                                      />
                                    </td>
                                  <% end %>
                                </tr>
                              <% end %>
                            </tbody>
                          </table>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <%= if not Enum.empty?(
                  Enum.reject(@modifier_groups, fn mg ->
                    Enum.any?(@item.modifier_groups || [], &(&1.id == mg.id))
                  end)
                ) do %>
                  <details class="group/assign-mods">
                    <summary class="list-none cursor-pointer flex items-center gap-1 text-[10px] font-black uppercase tracking-wider text-primary hover:opacity-80">
                      <span class="material-symbols-outlined text-sm">link</span> Link modifier group
                    </summary>
                    <div class="flex flex-wrap gap-2 mt-3">
                      <%= for mg <- Enum.reject(@modifier_groups, fn mg ->
                        Enum.any?(@item.modifier_groups || [], &(&1.id == mg.id))
                      end) do %>
                        <button
                          phx-click="assign_modifier_group"
                          phx-value-item_id={@item.id}
                          phx-value-group_id={mg.id}
                          phx-target={@myself}
                          type="button"
                          class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-dashed border-on-surface-variant/30 text-xs text-on-surface-variant hover:border-primary hover:text-primary transition-colors"
                        >
                          <span class="material-symbols-outlined" style="font-size: 14px;">add</span>
                          {mg.name}
                        </button>
                      <% end %>
                    </div>
                  </details>
                <% end %>
              </div>
            </details>

            <details class="group/advanced">
              <summary class="list-none flex items-center justify-between cursor-pointer py-2">
                <span class="text-xs font-black text-on-surface-variant uppercase tracking-wider">
                  Advanced
                </span>
                <span class="material-symbols-outlined text-sm text-on-surface-variant transition-transform group-open/advanced:rotate-180">
                  expand_more
                </span>
              </summary>
              <div class="pt-4 space-y-4">
                <div>
                  <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider mb-1">
                    Sort Order
                  </label>
                  <input
                    type="number"
                    form="item-form"
                    name="item[sort_order]"
                    value={@item.sort_order}
                    class="w-24 bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none"
                  />
                </div>
                <label class="flex items-center gap-3 cursor-pointer">
                  <input
                    type="checkbox"
                    phx-click="toggle_upsell"
                    phx-value-id={@item.id}
                    phx-target={@myself}
                    checked={@item.is_upsell}
                    class="rounded"
                  />
                  <div>
                    <span class="text-sm font-semibold text-on-surface">
                      Show as upsell suggestion
                    </span>
                    <p class="text-xs text-on-surface-variant">
                      May appear as a suggestion in other customers' baskets.
                    </p>
                  </div>
                </label>
              </div>
            </details>
          <% end %>
        </div>

        <div class="shrink-0 px-8 py-6 bg-surface-container-low">
          <div :if={not @show_delete_confirm} class="flex items-center justify-between gap-4">
            <button
              :if={is_struct(@item)}
              phx-click="delete_item"
              phx-target={@myself}
              type="button"
              class="text-error font-bold text-sm uppercase tracking-widest hover:opacity-70 transition-opacity"
            >
              Delete Item
            </button>
            <div class="flex gap-3 ml-auto">
              <button
                phx-click="cancel_edit"
                phx-target={@myself}
                type="button"
                class="text-on-surface-variant hover:text-on-surface font-bold text-sm px-5 py-2.5"
              >
                Cancel
              </button>
              <button
                type="submit"
                form="item-form"
                class="bg-primary text-white px-6 py-2.5 rounded-xl font-bold text-sm hover:opacity-90 transition-opacity phx-submit-loading:opacity-70 phx-submit-loading:cursor-wait"
              >
                <span class="phx-submit-loading:!hidden">
                  {if @item == :new or is_nil(@item), do: "Add Item", else: "Save Changes"}
                </span>
                <span class="hidden phx-submit-loading:!flex items-center justify-center gap-2">
                  Saving... <.icon name="hero-arrow-path" class="size-4 animate-spin" />
                </span>
              </button>
            </div>
          </div>

          <div
            :if={@show_delete_confirm}
            class="bg-error-container rounded-lg p-4 flex items-center justify-between gap-4"
          >
            <p class="text-sm font-bold text-on-error-container">
              Delete {if is_struct(@item), do: @item.name, else: "this item"}? This cannot be undone.
            </p>
            <div class="flex gap-2 shrink-0">
              <button
                phx-click="cancel_delete"
                phx-target={@myself}
                type="button"
                class="text-on-error-container/70 hover:text-on-error-container font-bold text-sm px-3 py-2"
              >
                Keep it
              </button>
              <button
                phx-click="confirm_delete_item"
                phx-target={@myself}
                type="button"
                class="bg-error text-on-error px-4 py-2 rounded-lg font-bold text-sm phx-click-loading:opacity-70 phx-click-loading:cursor-wait"
              >
                <span class="phx-click-loading:!hidden">Yes, Delete</span>
                <span class="hidden phx-click-loading:!flex items-center justify-center gap-2">
                  <.icon name="hero-arrow-path" class="size-3 animate-spin" />
                </span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :item, :any, default: nil
  attr :uploads, :any, required: true
  attr :myself, :any, required: true

  defp drawer_core_fields(assigns) do
    ~H"""
    <div class="space-y-5">
      <div>
        <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider mb-1">
          Name
        </label>
        <input
          type="text"
          name="item[name]"
          value={if @item, do: @item.name, else: ""}
          required
          autofocus
          placeholder="e.g. Classic Margherita"
          class="w-full bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none"
        />
      </div>

      <%= if is_nil(@item) or Enum.empty?(@item.sizes || []) do %>
        <div>
          <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider mb-1">
            Price (CAD)
          </label>
          <input
            type="text"
            name="item[price]"
            value={if @item, do: money_amount(@item.price), else: ""}
            inputmode="decimal"
            placeholder="e.g. 14.50"
            class="w-full bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none"
          />
        </div>
      <% else %>
        <input type="hidden" name="item[price]" value="" />
        <p class="text-xs text-on-surface-variant italic">
          Price is set per size — expand Sizes below to manage.
        </p>
      <% end %>

      <div>
        <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider mb-1">
          Description
        </label>
        <textarea
          name="item[description]"
          rows="3"
          placeholder="Describe the dish…"
          class="w-full bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none resize-none"
        >{if @item, do: @item.description, else: ""}</textarea>
      </div>

      <div class="space-y-2">
        <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider">
          Images
        </label>
        <div :if={@item && @item.images != []} class="flex flex-wrap gap-2">
          <div :for={img <- Enum.sort_by(@item.images, & &1.position)} class="relative group">
            <img src={img.url} alt="item image" class="h-16 w-16 rounded-lg object-cover" />
            <button
              type="button"
              phx-click="delete_image"
              phx-value-id={img.id}
              phx-target={@myself}
              class="absolute -top-1.5 -right-1.5 bg-error text-on-error rounded-full w-5 h-5 flex items-center justify-center text-xs font-bold opacity-0 group-hover:opacity-100 transition-opacity"
            >
              ×
            </button>
          </div>
        </div>
        <div :if={@item && @item.images == [] && @item.image_url} class="relative group w-fit">
          <img
            src={@item.image_url}
            alt="item image"
            class="h-16 w-16 rounded-lg object-cover opacity-50"
          />
          <p class="text-[10px] text-on-surface-variant mt-1">Legacy URL</p>
        </div>
        <.live_file_input
          upload={@uploads.item_image}
          class="text-sm text-on-surface-variant file:mr-3 file:py-1.5 file:px-3 file:rounded-lg file:border-0 file:bg-surface-container file:text-xs file:font-bold file:uppercase file:tracking-wider file:cursor-pointer"
        />
        <p class="text-[10px] text-on-surface-variant">Up to 5 images, or paste a URL below.</p>
        <input
          type="text"
          name="item[image_url]"
          value={if @item, do: @item.image_url || "", else: ""}
          placeholder="https://…"
          class="w-full bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none"
        />
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Modifier Group Drawer (functional component)
  # ---------------------------------------------------------------------------

  attr :group, :any, default: nil
  attr :open_group_id, :any, default: nil
  attr :show_group_delete_confirm, :boolean, default: false
  attr :editing_modifier_id, :any, default: nil
  attr :adding_modifier, :boolean, default: false
  attr :myself, :any, required: true

  defp modifier_group_drawer(assigns) do
    ~H"""
    <div
      id="group-drawer-wrapper"
      class={[
        "fixed inset-0 z-40 transition-all duration-300",
        if(@open_group_id, do: "visible", else: "invisible pointer-events-none")
      ]}
    >
      <div
        class={[
          "absolute inset-0 bg-black/30 transition-opacity duration-300",
          if(@open_group_id, do: "opacity-100", else: "opacity-0")
        ]}
        phx-click="cancel_group_edit"
        phx-target={@myself}
      >
      </div>

      <div class={[
        "absolute top-0 right-0 bottom-0 w-full md:w-[560px] bg-background flex flex-col",
        "shadow-[-24px_0px_64px_rgba(0,0,0,0.10)] transition-transform duration-300 ease-out",
        if(@open_group_id, do: "translate-x-0", else: "translate-x-full")
      ]}>
        <div class="flex items-center justify-between px-8 py-6 shrink-0 bg-background/95 backdrop-blur-sm border-b border-on-surface/5">
          <h2 class="font-headline text-2xl font-black text-on-surface tracking-tight">
            {if @group == :new or is_nil(@group), do: "New Group", else: @group.name}
          </h2>
          <button
            phx-click="cancel_group_edit"
            phx-target={@myself}
            class="w-10 h-10 flex items-center justify-center rounded-full bg-surface-container-low hover:bg-surface-container transition-all"
          >
            <span class="material-symbols-outlined">close</span>
          </button>
        </div>

        <div class="flex-1 overflow-y-auto px-8 py-6 space-y-8">
          <%= if @group == :new do %>
            <form id="group-form" phx-submit="create_modifier_group" phx-target={@myself} class="space-y-5">
              <div>
                <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider mb-1">
                  Name
                </label>
                <input
                  type="text"
                  name="group[name]"
                  required
                  autofocus
                  placeholder="e.g. Extra Toppings, Protein Choice"
                  class="w-full bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none"
                />
              </div>

              <label class="flex items-start gap-3 cursor-pointer">
                <input
                  type="checkbox"
                  name="group[required]"
                  value="true"
                  class="rounded mt-0.5"
                />
                <div>
                  <span class="text-sm font-semibold text-on-surface">Required</span>
                  <p class="text-xs text-on-surface-variant">
                    Customers must choose at least one option before adding to cart.
                  </p>
                </div>
              </label>

              <details class="group/limits">
                <summary class="list-none flex items-center justify-between cursor-pointer py-2">
                  <span class="text-xs font-black text-on-surface-variant uppercase tracking-wider">
                    Selection Limits
                  </span>
                  <span class="material-symbols-outlined text-sm text-on-surface-variant transition-transform group-open/limits:rotate-180">
                    expand_more
                  </span>
                </summary>
                <div class="pt-3 space-y-4">
                  <div>
                    <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider mb-1">
                      Min Selections
                    </label>
                    <input
                      type="number"
                      name="group[min_selections]"
                      placeholder="0"
                      min="0"
                      class="w-full bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none"
                    />
                  </div>
                  <div>
                    <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider mb-1">
                      Max Selections
                    </label>
                    <div class="flex items-center gap-3">
                      <input
                        type="number"
                        name="group[max_selections]"
                        placeholder=""
                        min="1"
                        class="w-28 bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none"
                      />
                      <span class="text-[10px] font-bold uppercase tracking-wider bg-primary/10 text-primary px-2 py-1 rounded-full">
                        Unlimited
                      </span>
                    </div>
                    <p class="text-xs text-on-surface-variant mt-1.5">Leave blank for unlimited</p>
                  </div>
                </div>
              </details>
            </form>
          <% end %>

          <%= if is_struct(@group) do %>
            <form id="group-form" phx-submit="save_group" phx-target={@myself} class="space-y-5">
              <input type="hidden" name="group[id]" value={@group.id} />
              <div>
                <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider mb-1">
                  Name
                </label>
                <input
                  type="text"
                  name="group[name]"
                  value={@group.name}
                  required
                  autofocus
                  placeholder="e.g. Extra Toppings, Protein Choice"
                  class="w-full bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none"
                />
              </div>

              <label class="flex items-start gap-3 cursor-pointer">
                <input
                  type="checkbox"
                  name="group[required]"
                  value="true"
                  checked={@group.required}
                  class="rounded mt-0.5"
                />
                <div>
                  <span class="text-sm font-semibold text-on-surface">Required</span>
                  <p class="text-xs text-on-surface-variant">
                    Customers must choose at least one option before adding to cart.
                  </p>
                </div>
              </label>

              <details class="group/limits">
                <summary class="list-none flex items-center justify-between cursor-pointer py-2">
                  <div class="flex items-center gap-2">
                    <span class="text-xs font-black text-on-surface-variant uppercase tracking-wider">
                      Selection Limits
                    </span>
                    <span class="text-[10px] text-on-surface-variant/60 font-medium normal-case tracking-normal">
                      {cond do
                        @group.min_selections > 0 and @group.max_selections && @group.max_selections < 99 ->
                          "min #{@group.min_selections} · max #{@group.max_selections}"
                        @group.min_selections > 0 ->
                          "min #{@group.min_selections} · unlimited max"
                        @group.max_selections && @group.max_selections < 99 ->
                          "max #{@group.max_selections}"
                        true ->
                          "unlimited"
                      end}
                    </span>
                  </div>
                  <span class="material-symbols-outlined text-sm text-on-surface-variant transition-transform group-open/limits:rotate-180">
                    expand_more
                  </span>
                </summary>
                <div class="pt-3 space-y-4">
                  <div>
                    <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider mb-1">
                      Min Selections
                    </label>
                    <input
                      type="number"
                      name="group[min_selections]"
                      value={@group.min_selections}
                      placeholder="0"
                      min="0"
                      class="w-full bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none"
                    />
                  </div>
                  <div>
                    <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider mb-1">
                      Max Selections
                    </label>
                    <div class="flex items-center gap-3">
                      <input
                        type="number"
                        name="group[max_selections]"
                        value={if @group.max_selections && @group.max_selections < 99, do: @group.max_selections, else: ""}
                        placeholder=""
                        min="1"
                        class="w-28 bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none"
                      />
                      <span
                        :if={is_nil(@group.max_selections) or @group.max_selections >= 99}
                        class="text-[10px] font-bold uppercase tracking-wider bg-primary/10 text-primary px-2 py-1 rounded-full"
                      >
                        Unlimited
                      </span>
                    </div>
                    <p class="text-xs text-on-surface-variant mt-1.5">Leave blank for unlimited</p>
                  </div>
                </div>
              </details>

              <details class="group/adv">
                <summary class="list-none flex items-center justify-between cursor-pointer py-2">
                  <span class="text-xs font-black text-on-surface-variant uppercase tracking-wider">
                    Advanced
                  </span>
                  <span class="material-symbols-outlined text-sm text-on-surface-variant transition-transform group-open/adv:rotate-180">
                    expand_more
                  </span>
                </summary>
                <div class="pt-3">
                  <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider mb-1">
                    Sort Order
                  </label>
                  <input
                    type="number"
                    name="group[sort_order]"
                    value={@group.sort_order}
                    class="w-24 bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none"
                  />
                </div>
              </details>
            </form>

            <div class="space-y-3">
              <div class="flex items-center justify-between">
                <span class="text-xs font-black text-on-surface-variant uppercase tracking-wider">
                  Options
                  <span :if={not Enum.empty?(@group.modifiers || [])} class="ml-1 text-primary">
                    ({length(@group.modifiers)})
                  </span>
                </span>
                <button
                  :if={not @adding_modifier}
                  phx-click="add_modifier"
                  phx-target={@myself}
                  type="button"
                  class="flex items-center gap-1 text-[0.65rem] font-black uppercase tracking-widest text-primary hover:opacity-70 transition-colors"
                >
                  <span class="material-symbols-outlined text-sm">add_circle</span> Add option
                </button>
              </div>

              <p :if={Enum.empty?(@group.modifiers || []) and not @adding_modifier} class="text-sm text-on-surface-variant italic">
                No options yet. Add options for customers to choose from.
              </p>

              <div class="space-y-1">
                <%= for modifier <- (@group.modifiers || []) do %>
                  <%= if to_string(@editing_modifier_id) == to_string(modifier.id) do %>
                    <form
                      phx-submit="save_modifier"
                      phx-target={@myself}
                      class="bg-surface-container rounded-lg p-3 space-y-3 border border-primary/20"
                    >
                      <input type="hidden" name="modifier[id]" value={modifier.id} />
                      <div class="grid grid-cols-2 gap-3">
                        <div>
                          <label class="block text-[10px] font-bold text-on-surface-variant uppercase tracking-widest mb-1">
                            Name
                          </label>
                          <input
                            type="text"
                            name="modifier[name]"
                            value={modifier.name}
                            required
                            autofocus
                            class="w-full bg-surface-container-highest border-0 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-primary outline-none"
                          />
                        </div>
                        <div>
                          <label class="block text-[10px] font-bold text-on-surface-variant uppercase tracking-widest mb-1">
                            Price Add-on
                          </label>
                          <input
                            type="text"
                            name="modifier[price_delta]"
                            value={if modifier.price_delta, do: money_amount(modifier.price_delta), else: ""}
                            placeholder="0.00"
                            inputmode="decimal"
                            class="w-full bg-surface-container-highest border-0 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-primary outline-none"
                          />
                        </div>
                      </div>
                      <div class="flex items-center justify-between gap-3">
                        <label class="flex items-center gap-2 text-sm text-on-surface-variant cursor-pointer">
                          <input
                            type="checkbox"
                            name="modifier[available]"
                            value="true"
                            checked={modifier.available}
                            class="rounded"
                          /> Available
                        </label>
                        <div class="flex items-center gap-2">
                          <label class="text-xs text-on-surface-variant">Sort</label>
                          <input
                            type="number"
                            name="modifier[sort_order]"
                            value={modifier.sort_order}
                            class="w-16 bg-surface-container-highest border-0 rounded px-2 py-1.5 text-xs focus:ring-1 focus:ring-primary outline-none"
                          />
                          <button
                            type="submit"
                            class="bg-primary text-white px-3 py-1.5 rounded-lg text-xs font-bold phx-submit-loading:opacity-70 phx-submit-loading:cursor-wait"
                          >
                            <span class="phx-submit-loading:!hidden">Save</span>
                            <span class="hidden phx-submit-loading:!flex items-center justify-center">
                              <.icon name="hero-arrow-path" class="size-3 animate-spin" />
                            </span>
                          </button>
                          <button
                            type="button"
                            phx-click="cancel_edit_modifier"
                            phx-target={@myself}
                            class="text-on-surface-variant hover:text-on-surface text-xs px-2 py-1.5"
                          >
                            Cancel
                          </button>
                        </div>
                      </div>
                    </form>
                  <% else %>
                    <div class="flex items-center gap-2 px-2 py-2 rounded-lg hover:bg-surface-container-low group/mod">
                      <button
                        phx-click="toggle_modifier_available"
                        phx-value-id={modifier.id}
                        phx-target={@myself}
                        type="button"
                        title={if modifier.available, do: "Available — click to 86", else: "Unavailable — click to restore"}
                        class="shrink-0"
                      >
                        <span class={[
                          "material-symbols-outlined transition-colors",
                          if(modifier.available,
                            do: "text-primary",
                            else: "text-on-surface-variant/40"
                          )
                        ]} style="font-size: 18px;">
                          {if modifier.available, do: "toggle_on", else: "toggle_off"}
                        </span>
                      </button>
                      <span class={[
                        "flex-1 text-sm",
                        if(modifier.available, do: "text-on-surface", else: "text-on-surface-variant line-through")
                      ]}>
                        {modifier.name}
                      </span>
                      <span class="text-xs text-on-surface-variant whitespace-nowrap">
                        {if modifier.price_delta, do: "+#{format_money(modifier.price_delta)}", else: "Free"}
                      </span>
                      <div class="flex items-center gap-0.5 opacity-0 group-hover/mod:opacity-100 transition-opacity">
                        <button
                          phx-click="edit_modifier"
                          phx-value-id={modifier.id}
                          phx-target={@myself}
                          type="button"
                          class="text-on-surface-variant hover:text-primary transition-colors p-1"
                          title="Edit option"
                        >
                          <span class="material-symbols-outlined" style="font-size: 16px;">edit</span>
                        </button>
                        <button
                          phx-click="delete_modifier"
                          phx-value-id={modifier.id}
                          phx-target={@myself}
                          type="button"
                          class="text-on-surface-variant hover:text-error transition-colors p-1"
                          title="Delete option"
                        >
                          <span class="material-symbols-outlined" style="font-size: 16px;">delete</span>
                        </button>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>

              <form
                :if={@adding_modifier}
                phx-submit="create_modifier"
                phx-target={@myself}
                class="flex flex-wrap items-center gap-2 pt-2"
              >
                <input
                  type="text"
                  name="modifier[name]"
                  required
                  autofocus
                  placeholder="Option name"
                  class="flex-[2] min-w-[140px] bg-surface-container-low border-0 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-primary outline-none"
                />
                <input
                  type="text"
                  name="modifier[price_delta]"
                  placeholder="+0.00"
                  inputmode="decimal"
                  class="flex-1 min-w-[80px] bg-surface-container-low border-0 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-primary outline-none"
                />
                <button
                  type="submit"
                  class="bg-primary text-white px-4 py-2 rounded-lg text-sm font-bold phx-submit-loading:opacity-70 phx-submit-loading:cursor-wait"
                >
                  <span class="phx-submit-loading:!hidden">Add</span>
                  <span class="hidden phx-submit-loading:!flex items-center justify-center">
                    <.icon name="hero-arrow-path" class="size-3 animate-spin" />
                  </span>
                </button>
                <button
                  type="button"
                  phx-click="cancel_add_modifier"
                  phx-target={@myself}
                  class="text-on-surface-variant hover:text-on-surface p-2"
                >
                  <span class="material-symbols-outlined" style="font-size: 18px;">close</span>
                </button>
              </form>
            </div>
          <% end %>
        </div>

        <div class="shrink-0 px-8 py-6 bg-surface-container-low">
          <div :if={not @show_group_delete_confirm} class="flex items-center justify-between gap-4">
            <button
              :if={is_struct(@group)}
              phx-click="delete_group"
              phx-target={@myself}
              type="button"
              class="text-error font-bold text-sm uppercase tracking-widest hover:opacity-70 transition-opacity"
            >
              Delete Group
            </button>
            <div class="flex gap-3 ml-auto">
              <button
                phx-click="cancel_group_edit"
                phx-target={@myself}
                type="button"
                class="text-on-surface-variant hover:text-on-surface font-bold text-sm px-5 py-2.5"
              >
                Cancel
              </button>
              <button
                type="submit"
                form="group-form"
                class="bg-primary text-white px-6 py-2.5 rounded-xl font-bold text-sm hover:opacity-90 transition-opacity phx-submit-loading:opacity-70 phx-submit-loading:cursor-wait"
              >
                <span class="phx-submit-loading:!hidden">
                  {if @group == :new or is_nil(@group), do: "Create Group", else: "Save Changes"}
                </span>
                <span class="hidden phx-submit-loading:!flex items-center justify-center gap-2">
                  Saving... <.icon name="hero-arrow-path" class="size-4 animate-spin" />
                </span>
              </button>
            </div>
          </div>

          <div
            :if={@show_group_delete_confirm}
            class="bg-error-container rounded-lg p-4 flex items-center justify-between gap-4"
          >
            <p class="text-sm font-bold text-on-error-container">
              Delete {if is_struct(@group), do: @group.name, else: "this group"}? This cannot be undone.
            </p>
            <div class="flex gap-2 shrink-0">
              <button
                phx-click="cancel_delete_group"
                phx-target={@myself}
                type="button"
                class="text-on-error-container/70 hover:text-on-error-container font-bold text-sm px-3 py-2"
              >
                Keep it
              </button>
              <button
                phx-click="confirm_delete_group"
                phx-target={@myself}
                type="button"
                class="bg-error text-on-error px-4 py-2 rounded-lg font-bold text-sm phx-click-loading:opacity-70 phx-click-loading:cursor-wait"
              >
                <span class="phx-click-loading:!hidden">Yes, Delete</span>
                <span class="hidden phx-click-loading:!flex items-center justify-center gap-2">
                  <.icon name="hero-arrow-path" class="size-3 animate-spin" />
                </span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
