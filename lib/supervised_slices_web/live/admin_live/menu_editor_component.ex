defmodule SupervisedSlicesWeb.AdminLive.MenuEditorComponent do
  use SupervisedSlicesWeb, :live_component

  alias SupervisedSlices.Menu.{
    Category,
    MenuItem,
    MenuItemSize,
    MenuItemModifierGroup,
    MenuItemModifier,
    MenuItemModifierGroupLink,
    MenuItemUpsell,
    MenuImageUploader
  }

  def mount(socket) do
    {:ok,
     socket
     |> assign(:editing_item_id, nil)
     |> assign(:adding_to_category_id, nil)
     |> assign(:creating_category, false)
     |> assign(:adding_size_to_item_id, nil)
     |> assign(:creating_modifier_group, false)
     |> assign(:adding_modifier_to_group_id, nil)
     |> assign(:assigning_upsell_to_item_id, nil)
     |> allow_upload(:item_image,
       accept: ~w(.jpg .jpeg .png .webp .gif),
       max_entries: 1,
       max_file_size: 8_000_000
     )}
  end

  def update(%{ash_scope: scope} = assigns, socket) do
    socket =
      socket
      |> assign(:ash_scope, scope)
      |> assign_new(:categories, fn -> load_categories(scope) end)
      |> assign_new(:modifier_groups, fn -> load_modifier_groups(scope) end)

    {:ok, assign(socket, Map.drop(assigns, [:ash_scope]))}
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

    uploaded_url =
      consume_uploaded_entries(socket, :item_image, fn %{path: path}, entry ->
        {:ok, MenuImageUploader.upload(scope.current_tenant, path, entry.client_type)}
      end)
      |> List.first()

    attrs = %{
      name: params["name"],
      description: params["description"],
      price: parse_money(params["price"]),
      image_url: uploaded_url || params["image_url"],
      sort_order: String.to_integer(params["sort_order"] || "0")
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

    uploaded_url =
      consume_uploaded_entries(socket, :item_image, fn %{path: path}, entry ->
        {:ok, MenuImageUploader.upload(scope.current_tenant, path, entry.client_type)}
      end)
      |> List.first()

    item =
      MenuItem.create!(
        %{
          name: params["name"],
          description: params["description"],
          price: parse_money(params["price"]),
          image_url: uploaded_url || params["image_url"],
          sort_order: String.to_integer(params["sort_order"] || "0"),
          category_id: params["category_id"]
        },
        scope: scope
      )

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

  def handle_event("add_upsell_to_item", %{"item_id" => item_id}, socket) do
    {:noreply, assign(socket, assigning_upsell_to_item_id: item_id)}
  end

  def handle_event("cancel_add_upsell", _params, socket) do
    {:noreply, assign(socket, :assigning_upsell_to_item_id, nil)}
  end

  def handle_event(
        "assign_upsell",
        %{"item_id" => item_id, "upsell_item_id" => upsell_item_id},
        socket
      ) do
    %{ash_scope: scope} = socket.assigns

    MenuItemUpsell.assign!(
      %{source_menu_item_id: item_id, upsell_menu_item_id: upsell_item_id},
      scope: scope
    )

    categories = load_categories(scope)
    {:noreply, assign(socket, categories: categories, assigning_upsell_to_item_id: nil)}
  end

  def handle_event("remove_upsell", %{"id" => id}, socket) do
    %{ash_scope: scope} = socket.assigns
    MenuItemUpsell.get!(id, scope: scope) |> MenuItemUpsell.unassign!(scope: scope)
    categories = load_categories(scope)
    {:noreply, assign(socket, :categories, categories)}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="font-headline text-2xl font-black text-on-surface">
            Menu Atelier
          </h2>
          <p class="text-sm text-on-surface-variant mt-1">
            Curate your artisan offerings and modifiers
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
          class="bg-primary text-white px-5 py-2 rounded-md text-sm font-bold uppercase tracking-wide"
        >
          Save
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
            class="bg-surface-container-low rounded-lg p-3 space-y-3"
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
                /> Required
              </label>
            </div>
            <div class="flex items-center gap-2">
              <button
                type="submit"
                class="bg-primary text-white px-4 py-2 rounded-lg text-sm font-bold hover:opacity-90"
              >
                Add Group
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
            No modifier groups yet. Create one to apply options to multiple items.
          </p>
        <% else %>
          <div class="space-y-3">
            <%= for group <- @modifier_groups do %>
              <div class="bg-surface-container-low rounded-lg p-3 space-y-2">
                <div class="flex items-center gap-2">
                  <span class="flex-1 text-sm font-bold text-on-surface">
                    {group.name}
                  </span>
                  <%= if group.required do %>
                    <span class="text-[10px] font-bold uppercase tracking-wider bg-primary-fixed text-on-primary-fixed-variant px-2 py-0.5 rounded-full">
                      Required
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

                <div class="pl-2 space-y-1">
                  <%= for modifier <- group.modifiers || [] do %>
                    <div class="flex items-center gap-2 text-sm">
                      <span class="flex-1 text-on-surface">{modifier.name}</span>
                      <span class="text-xs text-on-surface-variant">
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
                        <span class="material-symbols-outlined" style="font-size: 14px;">close</span>
                      </button>
                    </div>
                  <% end %>

                  <%= if @adding_modifier_to_group_id == group.id do %>
                    <form
                      phx-submit="create_modifier"
                      phx-target={@myself}
                      class="flex items-center gap-2 mt-1"
                    >
                      <input type="hidden" name="modifier[modifier_group_id]" value={group.id} />
                      <input
                        type="text"
                        name="modifier[name]"
                        required
                        autofocus
                        placeholder="Option name"
                        class="flex-1 bg-white border-0 rounded-lg px-2 py-1.5 text-sm focus:ring-2 focus:ring-primary outline-none"
                      />
                      <input
                        type="text"
                        name="modifier[price_delta]"
                        placeholder="+0.00"
                        inputmode="decimal"
                        class="w-20 bg-white border-0 rounded-lg px-2 py-1.5 text-sm focus:ring-2 focus:ring-primary outline-none"
                      />
                      <button
                        type="submit"
                        class="bg-primary text-white px-3 py-1.5 rounded-lg text-sm font-bold hover:opacity-90"
                      >
                        Add
                      </button>
                      <button
                        type="button"
                        phx-click="cancel_add_modifier"
                        phx-target={@myself}
                        class="text-on-surface-variant hover:text-on-surface p-1"
                      >
                        <span class="material-symbols-outlined" style="font-size: 14px;">close</span>
                      </button>
                    </form>
                  <% else %>
                    <button
                      phx-click="add_modifier"
                      phx-value-group_id={group.id}
                      phx-target={@myself}
                      type="button"
                      class="flex items-center gap-1 text-xs text-on-surface-variant hover:text-on-surface transition-colors mt-1"
                    >
                      <span class="material-symbols-outlined text-primary" style="font-size: 14px;">
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
                class="bg-primary text-white px-5 py-2 rounded-md text-sm font-bold uppercase tracking-wide"
              >
                Save
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
            <div class="flex items-center gap-4 group">
              <h3 class="text-2xl font-black text-on-surface flex-1 font-headline tracking-tight">
                {category.name}
              </h3>
              <button
                phx-click="edit_category"
                phx-value-id={category.id}
                phx-target={@myself}
                class="opacity-0 group-hover:opacity-100 text-on-surface-variant/40 hover:text-primary transition-all p-1"
                title="Edit category"
              >
                <span class="material-symbols-outlined text-lg">edit</span>
              </button>
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
                          Image
                        </label>
                        <%= if item.image_url do %>
                          <img
                            src={item.image_url}
                            alt={item.name}
                            class="h-16 w-16 rounded-lg object-cover"
                          />
                        <% end %>
                        <div class="flex gap-2 items-center">
                          <.live_file_input
                            upload={@uploads.item_image}
                            class="text-sm text-on-surface-variant file:mr-3 file:py-1.5 file:px-3 file:rounded-lg file:border-0 file:bg-surface-container file:text-xs file:font-bold file:uppercase file:tracking-wider file:cursor-pointer"
                          />
                        </div>
                        <p class="text-[10px] text-on-surface-variant">
                          Or paste a URL below (upload takes priority)
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
                        class="bg-primary text-white px-6 py-2.5 rounded-xl font-bold hover:opacity-90 transition-opacity"
                      >
                        Save Changes
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
                      Assign global modifier groups to this item. Manage group options above.
                    </p>

                    <%= for group <- (item.modifier_groups || []) do %>
                      <div class="flex items-center gap-3 px-3 py-2 bg-surface-container-low rounded-lg">
                        <span class="flex-1 text-sm font-semibold text-on-surface">{group.name}</span>
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
                      <div class="flex flex-wrap gap-2">
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
                    <% end %>
                  </div>

                  <div class="border-t border-surface-container-low pt-4 space-y-3">
                    <div class="flex items-center justify-between">
                      <p class="text-xs font-bold text-on-surface-variant uppercase tracking-wider">
                        Upsells
                      </p>
                      <%= if @assigning_upsell_to_item_id != item.id do %>
                        <button
                          phx-click="add_upsell_to_item"
                          phx-value-item_id={item.id}
                          phx-target={@myself}
                          type="button"
                          class="flex items-center gap-1 text-sm text-primary hover:opacity-80 font-bold"
                        >
                          <span class="material-symbols-outlined" style="font-size: 16px;">
                            add_circle
                          </span>
                          Add upsell
                        </button>
                      <% end %>
                    </div>

                    <p class="text-xs text-on-surface-variant">
                      Items to suggest when this item is in a customer's basket.
                    </p>

                    <%= for link <- (item.upsell_links || []) do %>
                      <div class="flex items-center gap-3 px-3 py-2 bg-surface-container-low rounded-lg">
                        <%= if link.upsell_item.image_url do %>
                          <img
                            src={link.upsell_item.image_url}
                            alt={link.upsell_item.name}
                            class="w-8 h-8 rounded object-cover shrink-0"
                          />
                        <% else %>
                          <div class="w-8 h-8 rounded bg-surface-container-high flex items-center justify-center shrink-0">
                            <span
                              class="material-symbols-outlined text-on-surface-variant/30"
                              style="font-size: 16px;"
                            >
                              image
                            </span>
                          </div>
                        <% end %>
                        <span class="flex-1 text-sm font-semibold text-on-surface">
                          {link.upsell_item.name}
                        </span>
                        <span class="text-xs text-primary font-bold">
                          {if link.upsell_item.price,
                            do: format_money(link.upsell_item.price),
                            else: "—"}
                        </span>
                        <button
                          phx-click="remove_upsell"
                          phx-value-id={link.id}
                          phx-target={@myself}
                          type="button"
                          class="text-on-surface-variant hover:text-error transition-colors p-1"
                          title="Remove upsell"
                        >
                          <span class="material-symbols-outlined" style="font-size: 16px;">
                            link_off
                          </span>
                        </button>
                      </div>
                    <% end %>

                    <%= if @assigning_upsell_to_item_id == item.id do %>
                      <% assigned_ids = MapSet.new(item.upsell_links || [], & &1.upsell_menu_item_id) %>
                      <% available_items =
                        Enum.flat_map(@categories, & &1.menu_items)
                        |> Enum.reject(&(&1.id == item.id or MapSet.member?(assigned_ids, &1.id))) %>
                      <%= if Enum.empty?(available_items) do %>
                        <p class="text-xs text-on-surface-variant italic">
                          No other items available to add as upsells.
                        </p>
                        <button
                          type="button"
                          phx-click="cancel_add_upsell"
                          phx-target={@myself}
                          class="text-xs text-on-surface-variant hover:text-on-surface"
                        >
                          Cancel
                        </button>
                      <% else %>
                        <div class="flex flex-wrap gap-2">
                          <%= for candidate <- available_items do %>
                            <button
                              phx-click="assign_upsell"
                              phx-value-item_id={item.id}
                              phx-value-upsell_item_id={candidate.id}
                              phx-target={@myself}
                              type="button"
                              class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-dashed border-on-surface-variant/30 text-xs text-on-surface-variant hover:border-primary hover:text-primary transition-colors"
                            >
                              <span class="material-symbols-outlined" style="font-size: 14px;">
                                add
                              </span>
                              {candidate.name}
                            </button>
                          <% end %>
                          <button
                            type="button"
                            phx-click="cancel_add_upsell"
                            phx-target={@myself}
                            class="flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs text-on-surface-variant hover:text-on-surface transition-colors"
                          >
                            <span class="material-symbols-outlined" style="font-size: 14px;">
                              close
                            </span>
                            Cancel
                          </button>
                        </div>
                      <% end %>
                    <% end %>

                    <%= if Enum.empty?(item.upsell_links || []) and @assigning_upsell_to_item_id != item.id do %>
                      <p class="text-xs text-on-surface-variant italic">
                        No upsells yet. Add items to suggest when this is in the basket.
                      </p>
                    <% end %>
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

                    <%= for size <- Enum.sort_by(item.sizes || [], & &1.sort_order) do %>
                      <div class="flex items-center gap-3 px-3 py-2 bg-surface-container-low rounded-lg">
                        <span class="flex-1 text-sm text-on-surface">{size.name}</span>
                        <span class="text-sm font-bold text-primary">{format_money(size.price)}</span>
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
                        class="flex items-center gap-2"
                      >
                        <input type="hidden" name="size[menu_item_id]" value={item.id} />
                        <input
                          type="text"
                          name="size[name]"
                          required
                          autofocus
                          placeholder="e.g. Large"
                          class="flex-1 bg-surface-container-low border-0 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-primary outline-none"
                        />
                        <input
                          type="text"
                          name="size[price]"
                          required
                          placeholder="18.00"
                          inputmode="decimal"
                          class="w-28 bg-surface-container-low border-0 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-primary outline-none"
                        />
                        <button
                          type="submit"
                          class="bg-primary text-white px-4 py-2 rounded-lg text-sm font-bold hover:opacity-90"
                        >
                          Add
                        </button>
                        <button
                          type="button"
                          phx-click="cancel_add_size"
                          phx-target={@myself}
                          class="text-on-surface-variant hover:text-on-surface p-2"
                        >
                          <span class="material-symbols-outlined" style="font-size: 16px;">
                            close
                          </span>
                        </button>
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
                          "px-2 py-1 rounded text-[10px] font-black uppercase tracking-widest shadow-lg backdrop-blur-md",
                          if(item.available,
                            do: "bg-secondary-container/90 text-on-secondary-container",
                            else: "bg-surface-container-highest/90 text-on-surface-variant"
                          )
                        ]}
                      >
                        {if item.available, do: "LIVE", else: "OFF"}
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
                        <%= if not Enum.empty?(item.upsell_links || []) do %>
                          <span class="bg-surface-container-highest text-[9px] font-black uppercase tracking-widest px-2 py-0.5 rounded text-on-surface-variant">
                            {length(item.upsell_links)} UPSELLS
                          </span>
                        <% end %>
                      </div>
                      <button
                        phx-click="edit_item"
                        phx-value-id={item.id}
                        phx-target={@myself}
                        class="text-on-surface-variant/40 hover:text-primary transition-colors"
                      >
                        <span class="material-symbols-outlined text-lg">edit</span>
                      </button>
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
                  New artisan offering
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
                <div class="flex items-center gap-3 pt-2">
                  <button
                    type="submit"
                    class="bg-primary text-white px-6 py-2.5 rounded-md font-bold text-xs uppercase tracking-widest transition-all active:scale-95"
                  >
                    Add Offering
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
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_categories(scope) do
    Category.active!(
      scope: scope,
      load: [menu_items: [modifier_groups: [:modifiers], sizes: [], upsell_links: [:upsell_item]]]
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

  defp money_amount(nil), do: "0.00"
  defp money_amount(money), do: Decimal.to_string(money.amount, :normal)
end
