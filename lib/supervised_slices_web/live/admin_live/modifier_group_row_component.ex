defmodule SupervisedSlicesWeb.AdminLive.ModifierGroupRowComponent do
  use SupervisedSlicesWeb, :live_component

  alias SupervisedSlices.Menu.{MenuItemModifierGroup, MenuItemModifier}

  def mount(socket) do
    {:ok,
     socket
     |> assign(:expanded, false)
     |> assign(:editing, false)
     |> assign(:adding_modifier, false)
     |> assign(:show_delete_confirm, false)}
  end

  def update(%{group: group, ash_scope: scope} = _assigns, socket) do
    {:ok,
     socket
     |> assign(:group, group)
     |> assign(:ash_scope, scope)}
  end

  def handle_event("toggle_expanded", _params, socket) do
    {:noreply, assign(socket, :expanded, not socket.assigns.expanded)}
  end

  def handle_event("edit_group", _params, socket) do
    {:noreply, assign(socket, editing: true, show_delete_confirm: false)}
  end

  def handle_event("cancel_edit_group", _params, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  def handle_event("save_group", %{"group" => params}, socket) do
    %{ash_scope: scope, group: group} = socket.assigns

    MenuItemModifierGroup.update!(group, %{
      name: params["name"],
      required: Map.get(params, "required") == "true",
      min_selections: parse_int(params["min_selections"]),
      max_selections: parse_int(params["max_selections"])
    }, scope: scope)

    group = MenuItemModifierGroup.get!(group.id, scope: scope, load: [:modifiers])
    notify_parent(socket, reload_categories: true)
    {:noreply, assign(socket, group: group, editing: false)}
  end

  def handle_event("delete_group", _params, socket) do
    {:noreply, assign(socket, show_delete_confirm: true)}
  end

  def handle_event("cancel_delete_group", _params, socket) do
    {:noreply, assign(socket, show_delete_confirm: false)}
  end

  def handle_event("confirm_delete_group", _params, socket) do
    %{ash_scope: scope, group: group} = socket.assigns
    group = MenuItemModifierGroup.get!(group.id, scope: scope, load: :modifiers)
    Enum.each(group.modifiers, &MenuItemModifier.destroy!(&1, scope: scope))
    MenuItemModifierGroup.destroy!(group, scope: scope)
    notify_parent(socket, reload_modifier_groups: true, reload_categories: true)
    {:noreply, socket}
  end

  def handle_event("add_modifier", _params, socket) do
    {:noreply, assign(socket, adding_modifier: true, expanded: true)}
  end

  def handle_event("cancel_add_modifier", _params, socket) do
    {:noreply, assign(socket, :adding_modifier, false)}
  end

  def handle_event("create_modifier", %{"modifier" => params}, socket) do
    %{ash_scope: scope, group: group} = socket.assigns

    MenuItemModifier.create!(
      %{
        name: params["name"],
        price_delta: parse_money(params["price_delta"]),
        modifier_group_id: group.id
      },
      scope: scope
    )

    group = MenuItemModifierGroup.get!(group.id, scope: scope, load: [:modifiers])
    {:noreply, assign(socket, group: group, adding_modifier: false)}
  end

  def handle_event("delete_modifier", %{"id" => id}, socket) do
    %{ash_scope: scope, group: group} = socket.assigns
    MenuItemModifier.get!(id, scope: scope) |> MenuItemModifier.destroy!(scope: scope)
    group = MenuItemModifierGroup.get!(group.id, scope: scope, load: [:modifiers])
    {:noreply, assign(socket, :group, group)}
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-2">
      <%= if @editing do %>
        <form
          phx-submit="save_group"
          phx-target={@myself}
          class="bg-surface-container rounded-lg p-3 space-y-3 border border-primary/10"
        >
          <input type="hidden" name="group[id]" value={@group.id} />
          <input
            type="text"
            name="group[name]"
            value={@group.name}
            required
            autofocus
            placeholder="e.g. Extra Toppings"
            class="w-full bg-surface-container-highest border-0 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-primary outline-none"
          />
          <div class="grid grid-cols-2 gap-2">
            <div>
              <label class="block text-[10px] font-bold text-on-surface-variant uppercase tracking-widest mb-1">
                Min
              </label>
              <input
                type="number"
                name="group[min_selections]"
                value={@group.min_selections}
                min="0"
                placeholder="0"
                class="w-full bg-surface-container-highest border-0 rounded-lg px-3 py-2 text-xs focus:ring-2 focus:ring-primary outline-none"
              />
            </div>
            <div>
              <label class="block text-[10px] font-bold text-on-surface-variant uppercase tracking-widest mb-1">
                Max
              </label>
              <input
                type="number"
                name="group[max_selections]"
                value={@group.max_selections}
                min="1"
                placeholder="No limit"
                class="w-full bg-surface-container-highest border-0 rounded-lg px-3 py-2 text-xs focus:ring-2 focus:ring-primary outline-none"
              />
            </div>
          </div>
          <div class="flex items-center justify-between">
            <label class="flex items-center gap-2 text-sm text-on-surface-variant cursor-pointer">
              <input
                type="checkbox"
                name="group[required]"
                value="true"
                checked={@group.required}
                class="rounded"
              />
              Required
            </label>
            <div class="flex items-center gap-2">
              <button
                type="submit"
                class="bg-primary text-white px-3 py-1.5 rounded text-xs font-bold phx-submit-loading:opacity-70 phx-submit-loading:cursor-wait"
              >
                <span class="phx-submit-loading:!hidden">Save</span>
                <span class="hidden phx-submit-loading:!flex items-center justify-center">
                  <.icon name="hero-arrow-path" class="size-3 animate-spin" />
                </span>
              </button>
              <button
                type="button"
                phx-click="cancel_edit_group"
                phx-target={@myself}
                class="text-on-surface-variant hover:text-on-surface text-xs px-2 py-1.5"
              >
                Cancel
              </button>
            </div>
          </div>
        </form>
      <% else %>
        <%= if @show_delete_confirm do %>
          <div class="bg-error-container rounded-lg px-3 py-2 flex items-center gap-2">
            <p class="flex-1 text-xs font-bold text-on-error-container">
              Delete {@group.name}?
            </p>
            <button
              phx-click="cancel_delete_group"
              phx-target={@myself}
              type="button"
              class="text-on-error-container/60 hover:text-on-error-container text-xs px-2 py-1"
            >
              Keep
            </button>
            <button
              phx-click="confirm_delete_group"
              phx-target={@myself}
              type="button"
              class="bg-error text-on-error px-3 py-1 rounded text-xs font-bold phx-click-loading:opacity-70 phx-click-loading:cursor-wait"
            >
              <span class="phx-click-loading:!hidden">Delete</span>
              <span class="hidden phx-click-loading:!flex items-center justify-center gap-1">
                <.icon name="hero-arrow-path" class="size-3 animate-spin" />
              </span>
            </button>
          </div>
        <% else %>
          <div class="flex items-center gap-2">
            <button
              type="button"
              phx-click="toggle_expanded"
              phx-target={@myself}
              class="flex items-center gap-2 flex-1 text-left min-w-0"
            >
              <span class={[
                "material-symbols-outlined text-sm transition-transform duration-200 shrink-0",
                if(@expanded, do: "rotate-90")
              ]}>
                chevron_right
              </span>
              <span class="text-sm font-bold text-on-surface truncate">
                {@group.name}
              </span>
            </button>
            <span
              :if={@group.required}
              class="text-[10px] font-bold uppercase tracking-wider bg-primary-fixed text-on-primary-fixed-variant px-2 py-0.5 rounded-full shrink-0"
            >
              Req.
            </span>
            <span
              :if={@group.max_selections}
              class="text-[10px] font-bold uppercase tracking-wider bg-surface-container text-on-surface-variant px-2 py-0.5 rounded-full shrink-0"
            >
              {if @group.max_selections == 1, do: "1 only", else: "max #{@group.max_selections}"}
            </span>
            <span
              :if={@group.min_selections > 0 and not @group.required}
              class="text-[10px] font-bold uppercase tracking-wider bg-surface-container text-on-surface-variant px-2 py-0.5 rounded-full shrink-0"
            >
              min {@group.min_selections}
            </span>
            <button
              phx-click="edit_group"
              phx-target={@myself}
              type="button"
              class="text-on-surface-variant hover:text-primary transition-colors p-1 shrink-0"
              title="Edit group"
            >
              <span class="material-symbols-outlined" style="font-size: 16px;">edit</span>
            </button>
            <button
              phx-click="delete_group"
              phx-target={@myself}
              type="button"
              class="text-on-surface-variant hover:text-error transition-colors p-1 shrink-0"
              title="Delete group"
            >
              <span class="material-symbols-outlined" style="font-size: 16px;">delete</span>
            </button>
          </div>
        <% end %>
      <% end %>

      <div :if={@expanded and not @editing} class="pl-6 space-y-1.5">
        <div :for={modifier <- @group.modifiers || []} class="flex items-center gap-2 text-xs">
          <span class="flex-1 text-on-surface">{modifier.name}</span>
          <span class="text-[10px] text-on-surface-variant whitespace-nowrap">
            {if modifier.price_delta, do: "+#{format_money(modifier.price_delta)}", else: "Free"}
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

        <form
          phx-submit="create_modifier"
          phx-target={@myself}
          class="flex flex-col gap-2 mt-2 p-2 bg-surface-container-highest rounded-lg"
        >
          <input type="hidden" name="modifier[modifier_group_id]" value={@group.id} />
          <input
            type="text"
            name="modifier[name]"
            :if={@adding_modifier}
            required
            autofocus
            placeholder="Option name"
            class="w-full bg-surface-container border-0 rounded px-2 py-1.5 text-xs focus:ring-1 focus:ring-primary outline-none"
          />
          <div :if={@adding_modifier} class="flex items-center gap-2">
            <input
              type="text"
              name="modifier[price_delta]"
              placeholder="+0.00"
              inputmode="decimal"
              class="flex-1 bg-surface-container border-0 rounded px-2 py-1.5 text-xs focus:ring-1 focus:ring-primary outline-none"
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
              <span class="material-symbols-outlined" style="font-size: 14px;">close</span>
            </button>
          </div>
          <button
            :if={not @adding_modifier}
            type="button"
            phx-click="add_modifier"
            phx-target={@myself}
            class="flex items-center gap-1 text-[10px] font-black uppercase tracking-wider text-primary hover:opacity-70 transition-colors"
          >
            <span class="material-symbols-outlined" style="font-size: 14px;">add_circle</span>
            Add option
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp notify_parent(_socket, opts) do
    send_update(SupervisedSlicesWeb.AdminLive.MenuEditorComponent,
      id: "menu-editor",
      reload_modifier_groups: Keyword.get(opts, :reload_modifier_groups, false),
      reload_categories: Keyword.get(opts, :reload_categories, false)
    )
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
end
