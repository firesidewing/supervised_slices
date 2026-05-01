defmodule SupervisedSlicesWeb.AdminLive.ModifierGroupRowComponent do
  use SupervisedSlicesWeb, :live_component

  def mount(socket) do
    {:ok, socket}
  end

  def update(%{group: group, ash_scope: scope} = _assigns, socket) do
    {:ok,
     socket
     |> assign(:group, group)
     |> assign(:ash_scope, scope)}
  end

  def handle_event("open_in_drawer", _params, socket) do
    send_update(SupervisedSlicesWeb.AdminLive.MenuEditorComponent,
      id: "menu-editor",
      open_group_id: socket.assigns.group.id
    )

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="group/row">
      <button
        type="button"
        phx-click="open_in_drawer"
        phx-target={@myself}
        class="w-full flex items-center gap-2 px-2 py-2 rounded-lg hover:bg-surface-container transition-colors text-left"
      >
        <span class="flex-1 text-sm font-semibold text-on-surface truncate min-w-0">
          {@group.name}
        </span>
        <span
          :if={@group.required}
          class="tooltip tooltip-top shrink-0"
          data-tip="Customers must make a selection from this group before they can add the item to their cart"
        >
          <span class="text-[10px] font-bold uppercase tracking-wider bg-primary-fixed text-on-primary-fixed-variant px-2 py-0.5 rounded-full">
            Req.
          </span>
        </span>
        <span
          :if={@group.max_selections && @group.max_selections < 99}
          class="tooltip tooltip-top shrink-0"
          data-tip="Customers can pick up to this many options from this group"
        >
          <span class="text-[10px] font-bold uppercase tracking-wider bg-surface-container text-on-surface-variant px-2 py-0.5 rounded-full">
            {if @group.max_selections == 1, do: "1 only", else: "max #{@group.max_selections}"}
          </span>
        </span>
        <span class="text-[10px] text-on-surface-variant shrink-0">
          {length(@group.modifiers || [])} options
        </span>
        <span
          class="material-symbols-outlined text-on-surface-variant/50 group-hover/row:text-primary transition-colors shrink-0"
          style="font-size: 16px;"
        >
          chevron_right
        </span>
      </button>
    </div>
    """
  end
end
