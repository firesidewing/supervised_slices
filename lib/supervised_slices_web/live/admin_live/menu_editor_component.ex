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
    MenuImageUploader,
    MenuUpload
  }

  alias SupervisedSlices.Billing

  require Ash.Query

  def mount(socket) do
    {:ok,
     socket
     |> assign(:editing_item_id, nil)
     |> assign(:adding_to_category_id, nil)
     |> assign(:creating_category, false)
     |> assign(:adding_size_to_item_id, nil)
     |> assign(:creating_modifier_group, false)
     |> assign(:adding_modifier_to_group_id, nil)
     |> assign(:expanded_modifier_groups, %{})
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
    {:noreply, assign(socket, editing_item_id: id, adding_to_category_id: nil)}
  end

  def handle_event("add_item", %{"category_id" => id}, socket) do
    {:noreply, assign(socket, adding_to_category_id: id, editing_item_id: nil)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     assign(socket,
       editing_item_id: nil,
       adding_to_category_id: nil,
       adding_size_to_item_id: nil,
       adding_modifier_to_group_id: nil,
       creating_modifier_group: false
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
    {:noreply, assign(socket, categories: categories, editing_item_id: nil)}
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
     assign(socket, categories: categories, adding_to_category_id: nil, editing_item_id: item.id)}
  end

  # ---------------------------------------------------------------------------
  # Category events
  # ---------------------------------------------------------------------------

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

  def handle_event("add_size", %{"item_id" => item_id}, socket) do
    {:noreply,
     assign(socket,
       adding_size_to_item_id: item_id,
       adding_modifier_to_group_id: nil
     )}
  end

  def handle_event("cancel_add_size", _params, socket) do
    {:noreply, assign(socket, :adding_size_to_item_id, nil)}
  end

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
    {:noreply, assign(socket, categories: categories, adding_size_to_item_id: nil)}
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

    group =
      MenuItemModifierGroup.create!(
        %{
          name: params["name"],
          required: Map.get(params, "required") == "true"
        },
        scope: scope
      )

    modifier_groups = load_modifier_groups(scope)
    expanded = Map.put(socket.assigns.expanded_modifier_groups, group.id, true)

    {:noreply,
     assign(socket,
       modifier_groups: modifier_groups,
       creating_modifier_group: false,
       expanded_modifier_groups: expanded
     )}
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
       adding_size_to_item_id: nil
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

  def handle_event("toggle_modifier_group_expanded", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded_modifier_groups

    new_expanded =
      if Map.has_key?(expanded, id),
        do: Map.delete(expanded, id),
        else: Map.put(expanded, id, true)

    {:noreply, assign(socket, :expanded_modifier_groups, new_expanded)}
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

  def handle_event("upload_menu", _params, socket) do
    %{org: org} = socket.assigns

    uploaded_urls =
      consume_uploaded_entries(socket, :menu_file, fn %{path: path}, entry ->
        {:ok, MenuImageUploader.upload(org.id, path, entry.client_type)}
      end)

    case uploaded_urls do
      [url] ->
        case MenuUpload.create(%{file_url: url, organization_id: org.id}, authorize?: false) do
          {:ok, upload} ->
            {:noreply,
             socket
             |> put_flash(:info, "Menu upload started. It will be processed shortly.")
             |> assign(:current_upload, upload)}

          {:error, error} ->
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
    ~H"""
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
                <span :if={@purchasing_upload} class="material-symbols-outlined text-lg animate-spin">
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
              <form phx-submit="upload_menu" phx-target={@myself}>
                <.live_file_input upload={@uploads.menu_file} class="hidden" />
                <label
                  for={@uploads.menu_file.ref}
                  class="cursor-pointer bg-primary text-white px-6 py-2.5 rounded-md font-bold text-sm uppercase tracking-wide transition-all active:scale-95 shadow-sm inline-flex items-center gap-2"
                >
                  <span class="material-symbols-outlined text-lg">upload_file</span>
                  Choose File
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
              <div class="h-full bg-primary transition-all" style={"width: #{entry.progress}%"}></div>
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
                    <span class="material-symbols-outlined text-lg phx-click-loading:animate-spin">arrow_upward</span>
                  </button>
                  <button
                    phx-click="move_category"
                    phx-value-id={category.id}
                    phx-value-direction="down"
                    phx-target={@myself}
                    class="text-on-surface-variant/40 hover:text-primary p-1 phx-click-loading:opacity-50 phx-click-loading:cursor-wait"
                    title="Move down"
                  >
                    <span class="material-symbols-outlined text-lg phx-click-loading:animate-spin">arrow_downward</span>
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
              <%= for item <- category.menu_items do %>
                <%= if @editing_item_id == item.id do %>
                  <div class="bg-surface-container-lowest rounded-xl p-5 space-y-5">
                    <form phx-submit="save_item" phx-target={@myself} class="space-y-4">
                      <input type="hidden" name="item[id]" value={item.id} />
                      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <div>
                          <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider mb-1">
                            Name
                          </label>
                          <input
                            type="text"
                            name="item[name]"
                            value={item.name}
                            autofocus
                            class="w-full bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none"
                          />
                        </div>
                        <%= if Enum.empty?(item.sizes || []) do %>
                          <div>
                            <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider mb-1">
                              Base Price (CAD)
                            </label>
                            <input
                              type="text"
                              name="item[price]"
                              value={money_amount(item.price)}
                              inputmode="decimal"
                              placeholder="e.g. 14.50"
                              class="w-full bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none"
                            />
                          </div>
                        <% else %>
                          <input type="hidden" name="item[price]" value="" />
                        <% end %>
                        <div class="md:col-span-2">
                          <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider mb-1">
                            Description
                          </label>
                          <textarea
                            name="item[description]"
                            rows="2"
                            class="w-full bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none resize-none"
                          >{item.description}</textarea>
                        </div>
                        <div class="md:col-span-2 space-y-2">
                          <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider">
                            Images
                          </label>
                          <div :if={item.images != []} class="flex flex-wrap gap-2">
                            <div
                              :for={img <- Enum.sort_by(item.images, & &1.position)}
                              class="relative group"
                            >
                              <img
                                src={img.url}
                                alt={item.name}
                                class="h-16 w-16 rounded-lg object-cover"
                              />
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
                          <div :if={item.images == [] and item.image_url} class="relative group w-fit">
                            <img
                              src={item.image_url}
                              alt={item.name}
                              class="h-16 w-16 rounded-lg object-cover opacity-50"
                            />
                            <p class="text-[10px] text-on-surface-variant mt-1">Legacy URL</p>
                          </div>
                          <div class="flex gap-2 items-center">
                            <.live_file_input
                              upload={@uploads.item_image}
                              class="text-sm text-on-surface-variant file:mr-3 file:py-1.5 file:px-3 file:rounded-lg file:border-0 file:bg-surface-container file:text-xs file:font-bold file:uppercase file:tracking-wider file:cursor-pointer"
                            />
                          </div>
                          <p class="text-[10px] text-on-surface-variant">
                            Up to 5 images. Or paste a URL below for a single image.
                          </p>
                          <input
                            type="text"
                            name="item[image_url]"
                            value={item.image_url || ""}
                            placeholder="https://…"
                            class="w-full bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none"
                          />
                        </div>
                        <div>
                          <label class="block text-xs font-bold text-on-surface-variant uppercase tracking-wider mb-1">
                            Sort Order
                          </label>
                          <input
                            type="number"
                            name="item[sort_order]"
                            value={item.sort_order}
                            class="w-full bg-surface-container-low border-0 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary outline-none"
                          />
                        </div>
                      </div>
                      <div class="flex items-center gap-3 pt-2">
                        <button
                          type="submit"
                          class="bg-primary text-white px-6 py-2.5 rounded-xl font-bold hover:opacity-90 transition-opacity phx-submit-loading:opacity-70 phx-submit-loading:cursor-wait"
                        >
                          <span class="phx-submit-loading:!hidden">Save Changes</span>
                          <span class="hidden phx-submit-loading:!flex items-center justify-center gap-2">
                            Saving... <.icon name="hero-arrow-path" class="size-4 animate-spin" />
                          </span>
                        </button>
                        <button
                          type="button"
                          phx-click="cancel_edit"
                          phx-target={@myself}
                          class="text-on-surface-variant hover:text-on-surface font-medium px-4 py-2.5"
                        >
                          Cancel
                        </button>
                      </div>
                    </form>

                    <div class="border-t border-surface-container-low pt-4 space-y-3">
                      <p class="text-xs font-bold text-on-surface-variant uppercase tracking-wider">
                        Modifier Groups
                      </p>
                      <p class="text-xs text-on-surface-variant">
                        Assign global modifier groups to this item. Manage group options in the sidebar.
                      </p>

                      <%= for group <- (item.modifier_groups || []) do %>
                        <div class="flex items-center gap-3 px-3 py-2 bg-surface-container-low rounded-lg">
                          <span class="flex-1 text-sm font-semibold text-on-surface">
                            {group.name}
                          </span>
                          <%= if group.required do %>
                            <span class="text-[10px] font-bold uppercase tracking-wider bg-primary-fixed text-on-primary-fixed-variant px-2 py-0.5 rounded-full">
                              Required
                            </span>
                          <% end %>
                          <span class="text-xs text-on-surface-variant">
                            {length(group.modifiers || [])} options
                          </span>
                          <button
                            phx-click="remove_item_modifier_group"
                            phx-value-item_id={item.id}
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
                      <% end %>

                      <%= if not Enum.empty?(
                        Enum.reject(@modifier_groups, fn mg ->
                          Enum.any?(item.modifier_groups || [], &(&1.id == mg.id))
                        end)
                      ) do %>
                        <details class="group/assign-mods">
                          <summary class="list-none cursor-pointer flex items-center gap-1 text-[10px] font-black uppercase tracking-wider text-primary hover:opacity-80">
                            <span class="material-symbols-outlined text-sm">link</span>
                            Link modifier group
                          </summary>
                          <div class="flex flex-wrap gap-2 mt-3">
                            <%= for mg <- Enum.reject(@modifier_groups, fn mg ->
                            Enum.any?(item.modifier_groups || [], &(&1.id == mg.id))
                          end) do %>
                              <button
                                phx-click="assign_modifier_group"
                                phx-value-item_id={item.id}
                                phx-value-group_id={mg.id}
                                phx-target={@myself}
                                type="button"
                                class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-dashed border-on-surface-variant/30 text-xs text-on-surface-variant hover:border-primary hover:text-primary transition-colors"
                              >
                                <span class="material-symbols-outlined" style="font-size: 14px;">
                                  add
                                </span>
                                {mg.name}
                              </button>
                            <% end %>
                          </div>
                        </details>
                      <% end %>
                    </div>

                    <div class="border-t border-surface-container-low pt-4 space-y-3">
                      <p class="text-xs font-bold text-on-surface-variant uppercase tracking-wider">
                        Upsell
                      </p>
                      <p class="text-xs text-on-surface-variant">
                        When enabled, this item may appear as a suggestion in other customers' baskets.
                      </p>
                      <label class="flex items-center gap-3 cursor-pointer">
                        <input
                          type="checkbox"
                          phx-click="toggle_upsell"
                          phx-value-id={item.id}
                          phx-target={@myself}
                          checked={item.is_upsell}
                          class="rounded"
                        />
                        <span class="text-sm font-semibold text-on-surface">
                          Show as upsell suggestion
                        </span>
                      </label>
                    </div>

                    <div class="border-t border-surface-container-low pt-4 space-y-3">
                      <div class="flex items-center justify-between">
                        <p class="text-xs font-bold text-on-surface-variant uppercase tracking-wider">
                          Sizes
                        </p>
                        <%= if @adding_size_to_item_id != item.id do %>
                          <button
                            phx-click="add_size"
                            phx-value-item_id={item.id}
                            phx-target={@myself}
                            type="button"
                            class="flex items-center gap-1 text-sm text-primary hover:opacity-80 font-bold"
                          >
                            <span class="material-symbols-outlined" style="font-size: 16px;">
                              add_circle
                            </span>
                            Add size
                          </button>
                        <% end %>
                      </div>

                      <%= for size <- (item.sizes || []) do %>
                        <div class="flex items-center gap-3 px-3 py-2 bg-surface-container-low rounded-lg">
                          <span class="flex-1 text-sm text-on-surface">{size.name}</span>
                          <span class="text-sm font-bold text-primary">
                            {format_money(size.price)}
                          </span>
                          <button
                            phx-click="delete_size"
                            phx-value-id={size.id}
                            phx-target={@myself}
                            type="button"
                            class="text-on-surface-variant hover:text-error transition-colors p-1"
                          >
                            <span class="material-symbols-outlined" style="font-size: 14px;">
                              close
                            </span>
                          </button>
                        </div>
                      <% end %>

                      <%= if @adding_size_to_item_id == item.id do %>
                        <form
                          phx-submit="create_size"
                          phx-target={@myself}
                          class="flex flex-wrap items-center gap-2"
                        >
                          <input type="hidden" name="size[menu_item_id]" value={item.id} />
                          <input
                            type="text"
                            name="size[name]"
                            required
                            autofocus
                            placeholder="Name"
                            class="flex-[2] min-w-[100px] bg-surface-container-low border-0 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-primary outline-none"
                          />
                          <input
                            type="text"
                            name="size[price]"
                            required
                            placeholder="Price"
                            inputmode="decimal"
                            class="flex-1 min-w-[80px] bg-surface-container-low border-0 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-primary outline-none"
                          />
                          <div class="flex items-center gap-1">
                            <button
                              type="submit"
                              class="bg-primary text-white px-3 py-2 rounded-lg text-sm font-bold hover:opacity-90 whitespace-nowrap phx-submit-loading:opacity-70 phx-submit-loading:cursor-wait"
                            >
                              <span class="phx-submit-loading:!hidden">Add</span>
                              <span class="hidden phx-submit-loading:!flex items-center justify-center">
                                <.icon name="hero-arrow-path" class="size-3 animate-spin" />
                              </span>
                            </button>
                            <button
                              type="button"
                              phx-click="cancel_add_size"
                              phx-target={@myself}
                              class="text-on-surface-variant hover:text-on-surface p-1"
                            >
                              <span class="material-symbols-outlined" style="font-size: 16px;">
                                close
                              </span>
                            </button>
                          </div>
                        </form>
                      <% end %>

                      <%= if Enum.empty?(item.sizes || []) and @adding_size_to_item_id != item.id do %>
                        <p class="text-xs text-on-surface-variant italic">
                          No sizes yet. Add sizes to let customers choose (e.g. Small, Medium, Large).
                        </p>
                      <% end %>
                    </div>
                  </div>
                <% else %>
                  <div class={[
                    "bg-surface-container-low rounded-md flex flex-col shadow-sm overflow-hidden transition-all duration-300 group",
                    if(not item.available, do: "opacity-50 grayscale")
                  ]}>
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
                          <span class="phx-click-loading:!hidden">{if item.available, do: "LIVE", else: "OFF"}</span>
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
                            <span class="material-symbols-outlined text-lg phx-click-loading:animate-spin">arrow_upward</span>
                          </button>
                          <button
                            phx-click="move_item"
                            phx-value-id={item.id}
                            phx-value-direction="down"
                            phx-target={@myself}
                            class="text-on-surface-variant/40 hover:text-primary transition-colors p-1 phx-click-loading:opacity-50 phx-click-loading:cursor-wait"
                            title="Move down"
                          >
                            <span class="material-symbols-outlined text-lg phx-click-loading:animate-spin">arrow_downward</span>
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
                <% end %>
              <% end %>

              <%= if @adding_to_category_id == category.id do %>
                <form
                  phx-submit="create_item"
                  phx-target={@myself}
                  class="bg-surface-container-low rounded-md p-6 space-y-4 shadow-sm border-2 border-primary/20"
                >
                  <input type="hidden" name="item[category_id]" value={category.id} />
                  <h4 class="text-xs font-black text-on-surface uppercase tracking-[0.2em]">
                    New menu item
                  </h4>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <label class="block text-[10px] font-black text-on-surface-variant uppercase tracking-widest mb-1.5">
                        Name
                      </label>
                      <input
                        type="text"
                        name="item[name]"
                        required
                        autofocus
                        placeholder="e.g. Classic Margherita"
                        class="w-full bg-surface-container-highest border-0 rounded px-4 py-2.5 text-sm focus:ring-1 focus:ring-primary outline-none"
                      />
                    </div>
                    <div>
                      <label class="block text-[10px] font-black text-on-surface-variant uppercase tracking-widest mb-1.5">
                        Base Price (CAD)
                      </label>
                      <input
                        type="text"
                        name="item[price]"
                        placeholder="14.50"
                        inputmode="decimal"
                        class="w-full bg-surface-container-highest border-0 rounded px-4 py-2.5 text-sm focus:ring-1 focus:ring-primary outline-none"
                      />
                    </div>
                    <div>
                      <label class="block text-[10px] font-black text-on-surface-variant uppercase tracking-widest mb-1.5">
                        Sort Order
                      </label>
                      <input
                        type="number"
                        name="item[sort_order]"
                        value="0"
                        class="w-full bg-surface-container-highest border-0 rounded px-4 py-2.5 text-sm focus:ring-1 focus:ring-primary outline-none"
                      />
                    </div>
                    <div class="md:col-span-2">
                      <label class="block text-[10px] font-black text-on-surface-variant uppercase tracking-widest mb-1.5">
                        Description
                      </label>
                      <textarea
                        name="item[description]"
                        rows="2"
                        placeholder="Describe the dish…"
                        class="w-full bg-surface-container-highest border-0 rounded px-4 py-2.5 text-sm focus:ring-1 focus:ring-primary outline-none resize-none"
                      ></textarea>
                    </div>
                  </div>
                  <div>
                    <label class="block text-[10px] font-black text-on-surface-variant uppercase tracking-widest mb-1.5">
                      Images (optional)
                    </label>
                    <.live_file_input
                      upload={@uploads.item_image}
                      class="text-sm text-on-surface-variant file:mr-3 file:py-1.5 file:px-3 file:rounded-lg file:border-0 file:bg-surface-container file:text-xs file:font-bold file:uppercase file:tracking-wider file:cursor-pointer"
                    />
                  </div>
                  <div class="flex items-center gap-3 pt-2">
                    <button
                      type="submit"
                      class="bg-primary text-white px-6 py-2.5 rounded-md font-bold text-xs uppercase tracking-widest transition-all active:scale-95 phx-submit-loading:opacity-70 phx-submit-loading:cursor-wait"
                    >
                      <span class="phx-submit-loading:!hidden">Add Offering</span>
                      <span class="hidden phx-submit-loading:!flex items-center justify-center gap-2">
                        Adding... <.icon name="hero-arrow-path" class="size-4 animate-spin" />
                      </span>
                    </button>
                    <button
                      type="button"
                      phx-click="cancel_edit"
                      phx-target={@myself}
                      class="text-on-surface-variant/40 hover:text-on-surface font-bold text-xs uppercase tracking-widest px-4 py-2.5"
                    >
                      Cancel
                    </button>
                  </div>
                </form>
              <% else %>
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
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <aside class="w-full lg:w-80 shrink-0 space-y-6">
        <div class="bg-surface-container-low rounded-md p-6 space-y-6">
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

          <%= if @creating_modifier_group do %>
            <form
              phx-submit="create_modifier_group"
              phx-target={@myself}
              class="bg-surface-container-low rounded-lg p-3 space-y-3 shadow-sm border border-primary/10"
            >
              <div class="flex items-center gap-3">
                <input
                  type="text"
                  name="group[name]"
                  required
                  autofocus
                  placeholder="e.g. Extra Toppings"
                  class="flex-1 bg-white border-0 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-primary outline-none"
                />
                <label class="flex items-center gap-2 text-sm text-on-surface-variant whitespace-nowrap cursor-pointer">
                  <input
                    type="checkbox"
                    name="group[required]"
                    value="true"
                    class="rounded"
                  /> Req.
                </label>
              </div>
              <div class="flex items-center gap-2">
                <button
                  type="submit"
                  class="bg-primary text-white px-4 py-2 rounded-lg text-sm font-bold hover:opacity-90 flex-1 phx-submit-loading:opacity-70 phx-submit-loading:cursor-wait"
                >
                  <span class="phx-submit-loading:!hidden">Save</span>
                  <span class="hidden phx-submit-loading:!flex items-center justify-center gap-2">
                    <.icon name="hero-arrow-path" class="size-4 animate-spin" />
                  </span>
                </button>
                <button
                  type="button"
                  phx-click="cancel_add_modifier_group"
                  phx-target={@myself}
                  class="text-on-surface-variant hover:text-on-surface text-sm px-3 py-2"
                >
                  Cancel
                </button>
              </div>
            </form>
          <% end %>

          <%= if Enum.empty?(@modifier_groups) do %>
            <p class="text-xs text-on-surface-variant italic">
              No modifier groups yet.
            </p>
          <% else %>
            <div class="space-y-4">
              <%= for group <- @modifier_groups do %>
                <div class="space-y-2">
                  <div class="flex items-center gap-2">
                    <button
                      type="button"
                      phx-click="toggle_modifier_group_expanded"
                      phx-value-id={group.id}
                      phx-target={@myself}
                      class="flex items-center gap-2 flex-1 text-left"
                    >
                      <span class={[
                        "material-symbols-outlined text-sm transition-transform duration-200",
                        if(Map.has_key?(@expanded_modifier_groups, group.id), do: "rotate-90")
                      ]}>
                        chevron_right
                      </span>
                      <span class="text-sm font-bold text-on-surface">
                        {group.name}
                      </span>
                    </button>
                    <%= if group.required do %>
                      <span class="text-[10px] font-bold uppercase tracking-wider bg-primary-fixed text-on-primary-fixed-variant px-2 py-0.5 rounded-full">
                        Req.
                      </span>
                    <% end %>
                    <button
                      phx-click="delete_modifier_group"
                      phx-value-id={group.id}
                      phx-target={@myself}
                      type="button"
                      class="text-on-surface-variant hover:text-error transition-colors p-1"
                      title="Delete group"
                    >
                      <span class="material-symbols-outlined" style="font-size: 16px;">delete</span>
                    </button>
                  </div>

                  <div
                    :if={Map.has_key?(@expanded_modifier_groups, group.id)}
                    class="pl-6 space-y-1.5"
                  >
                    <%= for modifier <- group.modifiers || [] do %>
                      <div class="flex items-center gap-2 text-xs">
                        <span class="flex-1 text-on-surface">{modifier.name}</span>
                        <span class="text-[10px] text-on-surface-variant whitespace-nowrap">
                          {if modifier.price_delta,
                            do: "+#{format_money(modifier.price_delta)}",
                            else: "Free"}
                        </span>
                        <button
                          phx-click="delete_modifier"
                          phx-value-id={modifier.id}
                          phx-target={@myself}
                          type="button"
                          class="text-on-surface-variant hover:text-error transition-colors p-0.5"
                        >
                          <span class="material-symbols-outlined" style="font-size: 14px;">
                            close
                          </span>
                        </button>
                      </div>
                    <% end %>

                    <%= if @adding_modifier_to_group_id == group.id do %>
                      <form
                        phx-submit="create_modifier"
                        phx-target={@myself}
                        class="flex flex-col gap-2 mt-2 p-2 bg-white rounded-lg shadow-sm border border-primary/10"
                      >
                        <input type="hidden" name="modifier[modifier_group_id]" value={group.id} />
                        <input
                          type="text"
                          name="modifier[name]"
                          required
                          autofocus
                          placeholder="Option name"
                          class="w-full bg-surface-container-highest border-0 rounded px-2 py-1.5 text-xs focus:ring-1 focus:ring-primary outline-none"
                        />
                        <div class="flex items-center gap-2">
                          <input
                            type="text"
                            name="modifier[price_delta]"
                            placeholder="+0.00"
                            inputmode="decimal"
                            class="flex-1 bg-surface-container-highest border-0 rounded px-2 py-1.5 text-xs focus:ring-1 focus:ring-primary outline-none"
                          />
                          <button
                            type="submit"
                            class="bg-primary text-white px-3 py-1.5 rounded text-xs font-bold hover:opacity-90 phx-submit-loading:opacity-70 phx-submit-loading:cursor-wait"
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
                            class="text-on-surface-variant hover:text-on-surface p-1"
                          >
                            <span class="material-symbols-outlined" style="font-size: 14px;">
                              close
                            </span>
                          </button>
                        </div>
                      </form>
                    <% else %>
                      <button
                        phx-click="add_modifier"
                        phx-value-group_id={group.id}
                        phx-target={@myself}
                        type="button"
                        class="flex items-center gap-1 text-[10px] font-black uppercase tracking-wider text-primary hover:opacity-70 transition-colors mt-1"
                      >
                        <span class="material-symbols-outlined" style="font-size: 14px;">
                          add_circle
                        </span>
                        Add option
                      </button>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </aside>
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
            modifier_groups: [:modifiers],
            sizes: MenuItemSize |> Ash.Query.sort(sort_order: :asc),
            images: []
          )
      ]
    )
  end

  defp load_modifier_groups(scope) do
    MenuItemModifierGroup.list!(scope: scope, load: [:modifiers], authorize?: false)
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
end
