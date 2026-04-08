defmodule SupervisedSlicesWeb.MenuLive.ItemComponent do
  use SupervisedSlicesWeb, :live_component

  def update(%{selected_item: new_item} = assigns, socket) do
    current_item_id = socket.assigns[:selected_item] && socket.assigns.selected_item.id
    needs_init = is_nil(current_item_id) or current_item_id != new_item.id

    socket = assign(socket, assigns)

    socket =
      if needs_init do
        default_size_id =
          case Enum.sort_by(new_item.sizes || [], & &1.sort_order) do
            [first | _] -> to_string(first.id)
            [] -> nil
          end

        assign(socket,
          selected_size_id: default_size_id,
          selected_modifiers: MapSet.new()
        )
      else
        socket
      end

    {:ok, socket}
  end

  def handle_event("select_size", %{"size_id" => size_id}, socket) do
    {:noreply, assign(socket, :selected_size_id, size_id)}
  end

  def handle_event("toggle_modifier", %{"modifier_id" => modifier_id}, socket) do
    mods = socket.assigns.selected_modifiers

    new_mods =
      if MapSet.member?(mods, modifier_id),
        do: MapSet.delete(mods, modifier_id),
        else: MapSet.put(mods, modifier_id)

    {:noreply, assign(socket, :selected_modifiers, new_mods)}
  end

  def handle_event("add_to_cart", _params, socket) do
    send(self(), {
      :item_component_add_to_cart,
      socket.assigns.selected_item.id,
      socket.assigns[:selected_size_id],
      MapSet.to_list(socket.assigns.selected_modifiers)
    })

    {:noreply, socket}
  end

  def render(assigns) do
    item = assigns.selected_item
    selected_size_id = assigns[:selected_size_id]
    selected_modifiers = assigns[:selected_modifiers] || MapSet.new()
    has_customization = not Enum.empty?(item.sizes || []) or not Enum.empty?(item.modifier_groups)

    assigns =
      assign(assigns,
        has_customization: has_customization,
        total_price: compute_total(item, selected_size_id, selected_modifiers)
      )

    ~H"""
    <div class="bg-background min-h-screen">
      <div class="pt-[4.5rem] pb-44 max-w-2xl mx-auto">
        <div
          :if={@selected_item.image_url}
          class="relative w-full aspect-[4/3] overflow-hidden"
        >
          <img
            src={@selected_item.image_url}
            alt={@selected_item.name}
            class="w-full h-full object-cover"
            style={"view-transition-name: item-img-#{@selected_item.id};"}
          />
          <div class="absolute inset-x-0 bottom-0 h-2/3 bg-gradient-to-b from-transparent to-background pointer-events-none" />
        </div>

        <div class="px-5 pt-8 space-y-10">
          <div>
            <h2 class="font-headline text-4xl font-extrabold tracking-tight text-on-surface leading-tight">
              {@selected_item.name}
            </h2>
            <p class="mt-4 text-on-surface-variant leading-relaxed text-base">
              {@selected_item.description}
            </p>
          </div>

          <div :if={not Enum.empty?(@selected_item.sizes || [])}>
            <div class="flex items-center gap-2 mb-4">
              <div class="w-[3px] h-4 bg-primary rounded-full" />
              <h3 class="font-body text-xs font-bold uppercase tracking-widest text-on-surface-variant">
                Choose a Size
              </h3>
            </div>
            <div class="space-y-2">
              <.size_row
                :for={size <- Enum.sort_by(@selected_item.sizes, & &1.sort_order)}
                size={size}
                selected={to_string(size.id) == @selected_size_id}
                myself={@myself}
              />
            </div>
          </div>

          <div :for={group <- @selected_item.modifier_groups}>
            <div class="flex items-center gap-2 mb-3">
              <div class="w-[3px] h-4 bg-primary rounded-full" />
              <h3 class="font-body text-xs font-bold uppercase tracking-widest text-on-surface-variant">
                {group.name}
              </h3>
            </div>
            <div class="space-y-2">
              <.modifier_row
                :for={modifier <- group.modifiers}
                modifier={modifier}
                item={@selected_item}
                selected={MapSet.member?(@selected_modifiers, to_string(modifier.id))}
                myself={@myself}
              />
            </div>
          </div>

          <div :if={not @has_customization}>
            <div class={[
              "flex items-center justify-between py-4 px-5 rounded-2xl bg-surface-container-lowest",
              "shadow-[0px_4px_16px_rgba(93,63,62,0.06)]",
              get_item_qty(@cart_items_map, @selected_item.id) > 0 && "ring-1 ring-primary/20"
            ]}>
              <span class="font-headline text-xl font-bold text-primary">
                {format_money(@selected_item.price)}
              </span>
              <div class="flex items-center bg-surface-container rounded-full p-1">
                <button
                  phx-click="update_quantity"
                  phx-value-item_id={@selected_item.id}
                  phx-value-delta="-1"
                  class={[
                    "w-8 h-8 flex items-center justify-center rounded-full transition-colors",
                    if(get_item_qty(@cart_items_map, @selected_item.id) > 0,
                      do: "bg-primary text-on-primary hover:bg-primary-container",
                      else: "text-on-surface-variant hover:bg-surface-container-high"
                    )
                  ]}
                  aria-label="Remove one"
                >
                  <span class="material-symbols-outlined text-lg">remove</span>
                </button>
                <span class="px-3 text-sm font-bold min-w-[2rem] text-center text-on-surface">
                  {get_item_qty(@cart_items_map, @selected_item.id)}
                </span>
                <button
                  phx-click="update_quantity"
                  phx-value-item_id={@selected_item.id}
                  phx-value-delta="1"
                  class="w-8 h-8 flex items-center justify-center rounded-full bg-primary text-on-primary hover:bg-primary-container transition-colors"
                  aria-label="Add one"
                >
                  <span class="material-symbols-outlined text-lg">add</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div :if={@has_customization} class="fixed bottom-24 left-0 right-0 px-5 z-40">
        <div class="max-w-2xl mx-auto">
          <button
            phx-click="add_to_cart"
            phx-target={@myself}
            class="w-full flex items-center justify-between bg-gradient-to-r from-primary to-primary-container text-on-primary font-bold text-base rounded-full px-6 py-4 shadow-[0px_8px_24px_rgba(185,0,39,0.30)] hover:scale-[1.01] transition-all active:scale-95"
          >
            <span>Add to Basket</span>
            <span :if={@total_price} class="font-headline text-lg">{format_money(@total_price)}</span>
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp size_row(assigns) do
    ~H"""
    <button
      phx-click="select_size"
      phx-value-size_id={@size.id}
      phx-target={@myself}
      class={[
        "w-full flex items-center justify-between px-4 py-3.5 rounded-2xl transition-all duration-200 text-left",
        if(@selected,
          do:
            "bg-primary/10 ring-1 ring-primary/25 shadow-[0px_4px_16px_rgba(185,0,39,0.08)]",
          else:
            "bg-surface-container-lowest shadow-[0px_2px_8px_rgba(93,63,62,0.04)] hover:bg-surface-container-low"
        )
      ]}
    >
      <div class="flex items-center gap-3">
        <div class={[
          "w-5 h-5 rounded-full border-2 flex items-center justify-center shrink-0 transition-colors",
          if(@selected, do: "border-primary", else: "border-on-surface-variant/40")
        ]}>
          <div :if={@selected} class="w-2.5 h-2.5 rounded-full bg-primary" />
        </div>
        <span class="font-semibold text-sm text-on-surface">{@size.name}</span>
      </div>
      <span class={[
        "font-bold text-sm",
        if(@selected, do: "text-primary", else: "text-on-surface-variant")
      ]}>
        {format_money(@size.price)}
      </span>
    </button>
    """
  end

  defp modifier_row(assigns) do
    ~H"""
    <button
      phx-click="toggle_modifier"
      phx-value-modifier_id={@modifier.id}
      phx-target={@myself}
      class={[
        "w-full flex items-center justify-between px-4 py-3.5 rounded-2xl transition-all duration-200 text-left",
        if(@selected,
          do:
            "bg-primary/10 ring-1 ring-primary/25 shadow-[0px_4px_16px_rgba(185,0,39,0.08)]",
          else:
            "bg-surface-container-lowest shadow-[0px_2px_8px_rgba(93,63,62,0.04)] hover:bg-surface-container-low"
        )
      ]}
    >
      <div class="flex-1 min-w-0 pr-4">
        <div class="text-sm font-semibold text-on-surface leading-snug">{@modifier.name}</div>
        <div class={[
          "text-xs font-medium mt-0.5",
          if(@selected, do: "text-primary", else: "text-on-surface-variant")
        ]}>
          {modifier_price_label(@item, @modifier)}
        </div>
      </div>
      <div class={[
        "w-6 h-6 rounded-full border-2 flex items-center justify-center shrink-0 transition-all",
        if(@selected, do: "bg-primary border-primary", else: "border-on-surface-variant/40")
      ]}>
        <span
          :if={@selected}
          class="material-symbols-outlined text-on-primary"
          style="font-size: 14px;"
        >check</span>
      </div>
    </button>
    """
  end

  defp compute_total(item, selected_size_id, selected_modifiers) do
    base =
      cond do
        not is_nil(selected_size_id) ->
          Enum.find_value(item.sizes || [], item.price, fn size ->
            if to_string(size.id) == selected_size_id, do: size.price
          end)

        not is_nil(item.price) ->
          item.price

        true ->
          nil
      end

    if is_nil(base) do
      nil
    else
      Enum.reduce(item.modifier_groups || [], base, fn group, acc ->
        Enum.reduce(group.modifiers || [], acc, fn modifier, inner_acc ->
          if MapSet.member?(selected_modifiers, to_string(modifier.id)) && modifier.price_delta do
            case Money.add(inner_acc, modifier.price_delta) do
              {:ok, total} -> total
              _ -> inner_acc
            end
          else
            inner_acc
          end
        end)
      end)
    end
  end

  defp modifier_price_label(item, modifier) do
    cond do
      modifier.price_delta -> "+#{format_money(modifier.price_delta)}"
      item.price -> format_money(item.price)
      true -> "Included"
    end
  end

  defp format_money(money) do
    Money.to_string!(money)
  rescue
    _ -> "#{money}"
  end

  defp get_item_qty(cart_items_map, item_id) do
    key = {to_string(item_id), nil, nil}
    get_in(cart_items_map, [key, :quantity]) || 0
  end
end
