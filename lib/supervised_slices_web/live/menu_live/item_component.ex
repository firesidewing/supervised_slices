defmodule SupervisedSlicesWeb.MenuLive.ItemComponent do
  use SupervisedSlicesWeb, :live_component

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <main class="pt-[4.5rem] pb-32 max-w-2xl mx-auto">
      <div class="relative w-full aspect-[4/3] overflow-hidden bg-surface-container-low">
        <img
          src={@selected_item.image_url || "https://placehold.co/600x450/f4f3f1/5d3f3e?text=🍕"}
          alt={@selected_item.name}
          class="w-full h-full object-cover"
          style={"view-transition-name: item-img-#{@selected_item.id};"}
        />
      </div>

      <div class="px-5 pt-6 space-y-8">
        <div>
          <h2
            class="text-3xl font-extrabold tracking-tight text-on-surface leading-tight"
            style="font-family: 'Plus Jakarta Sans', sans-serif;"
          >
            {@selected_item.name}
          </h2>
          <p class="mt-3 text-on-surface-variant leading-relaxed text-base">
            {@selected_item.description}
          </p>
        </div>

        <div :if={not Enum.empty?(@selected_item.sizes || [])}>
          <h3
            class="text-xs font-bold uppercase tracking-widest text-on-surface-variant mb-3"
            style="font-family: 'Be Vietnam Pro', sans-serif;"
          >
            Choose a Size
          </h3>
          <div class="space-y-2">
            <.size_row
              :for={size <- Enum.sort_by(@selected_item.sizes, & &1.sort_order)}
              size={size}
              item={@selected_item}
              cart_items_map={@cart_items_map}
            />
          </div>
        </div>

        <div :for={group <- @selected_item.modifier_groups}>
          <h3
            class="text-xs font-bold uppercase tracking-widest text-on-surface-variant mb-3"
            style="font-family: 'Be Vietnam Pro', sans-serif;"
          >
            {group.name}
          </h3>
          <div class="space-y-2">
            <.modifier_row
              :for={modifier <- group.modifiers}
              modifier={modifier}
              item={@selected_item}
              cart_items_map={@cart_items_map}
            />
          </div>
        </div>

        <div :if={
          Enum.empty?(@selected_item.sizes || []) &&
            Enum.empty?(@selected_item.modifier_groups)
        }>
          <div class="flex items-center justify-between py-2.5 px-4 rounded-xl bg-surface-container-low">
            <span class="text-base font-bold text-primary">
              {format_money(@selected_item.price)}
            </span>
            <div class="flex items-center bg-white rounded-full p-1 shadow-sm">
              <button
                phx-click="update_quantity"
                phx-value-item_id={@selected_item.id}
                phx-value-delta="-1"
                class="w-8 h-8 flex items-center justify-center rounded-full hover:bg-surface-container transition-colors"
                aria-label="Remove one"
              >
                <span class="material-symbols-outlined" style="font-size: 18px;">remove</span>
              </button>
              <span class="px-3 text-sm font-bold min-w-[2rem] text-center">
                {get_item_qty(@cart_items_map, @selected_item.id)}
              </span>
              <button
                phx-click="update_quantity"
                phx-value-item_id={@selected_item.id}
                phx-value-delta="1"
                class="w-8 h-8 flex items-center justify-center rounded-full bg-primary text-white hover:bg-primary-container transition-colors"
                aria-label="Add one"
              >
                <span class="material-symbols-outlined" style="font-size: 18px;">add</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </main>
    """
  end

  defp size_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between py-2.5 px-4 rounded-xl bg-surface-container-low">
      <span class="text-sm font-semibold text-on-surface">{@size.name}</span>
      <div class="flex items-center gap-4">
        <span class="text-sm font-bold text-primary">{format_money(@size.price)}</span>
        <div class="flex items-center bg-white rounded-full p-1 shadow-sm">
          <button
            phx-click="update_quantity"
            phx-value-item_id={@item.id}
            phx-value-size_id={@size.id}
            phx-value-delta="-1"
            class="w-8 h-8 flex items-center justify-center rounded-full hover:bg-surface-container transition-colors"
            aria-label={"Remove #{@size.name}"}
          >
            <span class="material-symbols-outlined" style="font-size: 18px;">remove</span>
          </button>
          <span class="px-3 text-sm font-bold min-w-[2rem] text-center">
            {get_size_qty(@cart_items_map, @item.id, @size.id)}
          </span>
          <button
            phx-click="update_quantity"
            phx-value-item_id={@item.id}
            phx-value-size_id={@size.id}
            phx-value-delta="1"
            class="w-8 h-8 flex items-center justify-center rounded-full bg-primary text-white hover:bg-primary-container transition-colors"
            aria-label={"Add #{@size.name}"}
          >
            <span class="material-symbols-outlined" style="font-size: 18px;">add</span>
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp modifier_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between py-2.5 px-4 rounded-xl bg-surface-container-low">
      <span class="text-sm font-semibold text-on-surface">{@modifier.name}</span>
      <div class="flex items-center gap-4">
        <span class="text-sm font-bold text-primary">
          {if @item.price,
            do: item_price(@item.price, @modifier.price_delta),
            else: if(@modifier.price_delta, do: "+#{format_money(@modifier.price_delta)}", else: "Free")}
        </span>
        <div class="flex items-center bg-white rounded-full p-1 shadow-sm">
          <button
            phx-click="update_quantity"
            phx-value-item_id={@item.id}
            phx-value-modifier_id={@modifier.id}
            phx-value-delta="-1"
            class="w-8 h-8 flex items-center justify-center rounded-full hover:bg-surface-container transition-colors"
            aria-label={"Remove #{@modifier.name}"}
          >
            <span class="material-symbols-outlined" style="font-size: 18px;">remove</span>
          </button>
          <span class="px-3 text-sm font-bold min-w-[2rem] text-center">
            {get_modifier_qty(@cart_items_map, @item.id, @modifier.id)}
          </span>
          <button
            phx-click="update_quantity"
            phx-value-item_id={@item.id}
            phx-value-modifier_id={@modifier.id}
            phx-value-delta="1"
            class="w-8 h-8 flex items-center justify-center rounded-full bg-primary text-white hover:bg-primary-container transition-colors"
            aria-label={"Add #{@modifier.name}"}
          >
            <span class="material-symbols-outlined" style="font-size: 18px;">add</span>
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp format_money(money) do
    Money.to_string!(money)
  rescue
    _ -> "#{money}"
  end

  defp item_price(base_price, nil), do: format_money(base_price)

  defp item_price(base_price, price_delta) do
    case Money.add(base_price, price_delta) do
      {:ok, total} -> format_money(total)
      _ -> format_money(base_price)
    end
  end

  defp get_item_qty(cart_items_map, item_id) do
    key = {to_string(item_id), nil, nil}
    get_in(cart_items_map, [key, :quantity]) || 0
  end

  defp get_size_qty(cart_items_map, item_id, size_id) do
    key = {to_string(item_id), to_string(size_id), nil}
    get_in(cart_items_map, [key, :quantity]) || 0
  end

  defp get_modifier_qty(cart_items_map, item_id, modifier_id) do
    key = {to_string(item_id), nil, to_string(modifier_id)}
    get_in(cart_items_map, [key, :quantity]) || 0
  end
end
