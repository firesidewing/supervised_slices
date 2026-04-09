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
      <div class="pt-32 pb-44 px-6 md:px-12 max-w-7xl mx-auto flex flex-col md:flex-row gap-12 items-start">
        <div
          :if={@selected_item.image_url}
          class="relative w-full md:w-1/2 aspect-[4/3] md:aspect-[3/4] overflow-hidden rounded-[3rem] shadow-2xl shadow-primary/10 sticky top-[6rem]"
        >
          <img
            src={@selected_item.image_url}
            alt={@selected_item.name}
            class="w-full h-full object-cover"
            style={"view-transition-name: item-img-#{@selected_item.id};"}
          />
          <div class="absolute inset-0 bg-gradient-to-t from-background/40 to-transparent" />
        </div>

        <div class="w-full md:w-1/2 space-y-16">
          <div>
            <h2 class="font-headline text-5xl md:text-7xl font-black tracking-tighter text-on-surface leading-[0.9]">
              {@selected_item.name}
            </h2>
            <p class="mt-8 text-on-surface-variant leading-relaxed text-xl font-medium opacity-80 max-w-xl">
              {@selected_item.description}
            </p>
          </div>

          <div :if={not Enum.empty?(@selected_item.sizes || [])} class="space-y-8">
            <div class="flex flex-col gap-1 px-1">
              <h3 class="font-headline text-2xl font-black tracking-tight text-on-surface uppercase italic">
                Choose a Size
              </h3>
            </div>
            <div class="grid grid-cols-1 gap-3">
              <.size_row
                :for={size <- Enum.sort_by(@selected_item.sizes, & &1.sort_order)}
                size={size}
                selected={to_string(size.id) == @selected_size_id}
                myself={@myself}
              />
            </div>
          </div>

          <div :for={group <- @selected_item.modifier_groups} class="space-y-8">
            <div class="flex flex-col gap-1 px-1">
              <h3 class="font-headline text-2xl font-black tracking-tight text-on-surface uppercase italic">
                {group.name}
              </h3>
            </div>
            <div class="grid grid-cols-1 gap-3">
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
              "flex items-center justify-between py-6 px-8 rounded-xl bg-surface-container-lowest",
              "shadow-[0px_12px_32px_rgba(93,63,62,0.08)]",
              "transition-all duration-300"
            ]}>
              <span class="font-headline text-2xl font-black text-primary">
                {format_money(@selected_item.price)}
              </span>
              <div class="flex items-center bg-surface-container rounded-full p-1.5 shadow-inner">
                <button
                  phx-click="update_quantity"
                  phx-value-item_id={@selected_item.id}
                  phx-value-delta="-1"
                  class={[
                    "w-10 h-10 flex items-center justify-center rounded-full transition-all active:scale-90",
                    if(get_item_qty(@cart_items_map, @selected_item.id) > 0,
                      do: "bg-primary text-on-primary shadow-lg shadow-primary/20",
                      else: "text-on-surface-variant hover:bg-surface-container-high"
                    )
                  ]}
                  aria-label="Remove one"
                >
                  <span class="material-symbols-outlined text-xl font-bold">remove</span>
                </button>
                <span class="px-4 text-base font-black min-w-[2.5rem] text-center text-on-surface">
                  {get_item_qty(@cart_items_map, @selected_item.id)}
                </span>
                <button
                  phx-click="update_quantity"
                  phx-value-item_id={@selected_item.id}
                  phx-value-delta="1"
                  class="w-10 h-10 flex items-center justify-center rounded-full bg-primary text-on-primary shadow-lg shadow-primary/20 hover:scale-105 transition-all active:scale-90"
                  aria-label="Add one"
                >
                  <span class="material-symbols-outlined text-xl font-bold">add</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

    <div :if={@has_customization} class="fixed bottom-24 left-0 right-0 px-6 z-40 md:left-auto md:right-12 md:bottom-12 md:w-[450px]">
        <div>
          <button
            phx-click="add_to_cart"
            phx-target={@myself}
            class="w-full flex items-center justify-between bg-gradient-to-r from-primary to-primary-container text-on-primary font-black text-lg rounded-2xl px-8 py-6 shadow-[0px_24px_48px_rgba(185,0,39,0.35)] hover:scale-[1.03] hover:shadow-[0px_32px_64px_rgba(185,0,39,0.45)] transition-all active:scale-95 group"
          >
            <span class="tracking-tight uppercase">Add to Basket</span>
            <span :if={@total_price} class="font-headline text-3xl group-hover:scale-110 transition-transform">{format_money(@total_price)}</span>
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
        "w-full flex items-center justify-between px-6 py-5 rounded-xl transition-all duration-300 text-left group",
        if(@selected,
          do:
            "bg-primary/5 shadow-[0px_8px_24px_rgba(185,0,39,0.06)] translate-x-1",
          else:
            "bg-surface-container-lowest shadow-[0px_4px_12px_rgba(93,63,62,0.04)] hover:bg-surface-container-low hover:-translate-y-0.5"
        )
      ]}
    >
      <div class="flex items-center gap-4">
        <div class={[
          "w-6 h-6 rounded-full border-2 flex items-center justify-center shrink-0 transition-all duration-300",
          if(@selected, do: "border-primary bg-primary scale-110", else: "border-on-surface-variant/30 group-hover:border-primary/50")
        ]}>
          <div :if={@selected} class="w-2.5 h-2.5 rounded-full bg-on-primary" />
        </div>
        <span class={["font-headline text-base font-black transition-colors", if(@selected, do: "text-primary", else: "text-on-surface")]}>
          {@size.name}
        </span>
      </div>
      <span class={[
        "font-headline text-base font-black transition-all",
        if(@selected, do: "text-primary scale-110", else: "text-on-surface-variant")
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
        "w-full flex items-center justify-between px-6 py-5 rounded-xl transition-all duration-300 text-left group",
        if(@selected,
          do:
            "bg-primary/5 shadow-[0px_8px_24px_rgba(185,0,39,0.06)] translate-x-1",
          else:
            "bg-surface-container-lowest shadow-[0px_4px_12px_rgba(93,63,62,0.04)] hover:bg-surface-container-low hover:-translate-y-0.5"
        )
      ]}
    >
      <div class="flex-1 min-w-0 pr-4">
        <div class={["text-base font-headline font-black transition-colors", if(@selected, do: "text-primary", else: "text-on-surface")]}>
          {@modifier.name}
        </div>
        <div class={[
          "text-xs font-black mt-1 uppercase tracking-widest transition-colors",
          if(@selected, do: "text-primary/70", else: "text-on-surface-variant opacity-70")
        ]}>
          {modifier_price_label(@item, @modifier)}
        </div>
      </div>
      <div class={[
        "w-7 h-7 rounded-lg border-2 flex items-center justify-center shrink-0 transition-all duration-300",
        if(@selected, do: "bg-primary border-primary rotate-0 scale-110", else: "border-on-surface-variant/30 group-hover:border-primary/50 rotate-90")
      ]}>
        <span
          :if={@selected}
          class="material-symbols-outlined text-on-primary font-black"
          style="font-size: 18px;"
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
