defmodule SupervisedSlicesWeb.MenuLive.MenuComponent do
  use SupervisedSlicesWeb, :live_component

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <main class="bg-background min-h-screen pt-20 pb-28 px-4 max-w-2xl mx-auto">
      <section :for={category <- @categories} class="mb-10">
        <div class="flex items-center gap-3 mb-5">
          <div class="w-[3px] h-6 bg-primary rounded-full shrink-0" />
          <h2 class="font-headline text-xl font-extrabold tracking-tight text-on-surface">
            {category.name}
          </h2>
        </div>

        <div class="space-y-3">
          <.menu_item_card
            :for={item <- category.menu_items}
            item={item}
            cart_items_map={@cart_items_map}
            org={@org}
          />
        </div>
      </section>

      <div :if={Enum.empty?(@categories)} class="text-center py-24 text-on-surface-variant">
        <span class="material-symbols-outlined text-6xl opacity-30">restaurant_menu</span>
        <p class="mt-4 text-lg font-medium">Menu coming soon</p>
      </div>
    </main>
    """
  end

  defp menu_item_card(assigns) do
    qty = get_item_qty(assigns.cart_items_map, assigns.item.id)

    customizable? =
      not Enum.empty?(assigns.item.sizes || []) or
        not Enum.empty?(assigns.item.modifier_groups || [])

    assigns = assign(assigns, qty: qty, customizable?: customizable?)

    ~H"""
    <div class={[
      "bg-surface-container-lowest rounded-2xl p-4 transition-colors duration-200",
      "shadow-[0px_2px_12px_rgba(93,63,62,0.06)]",
      @qty > 0 && "ring-1 ring-primary/20"
    ]}>
      <div class="flex gap-4 items-start">
        <.link
          :if={@item.image_url}
          navigate={~p"/menu/#{@org.slug}/item/#{@item.id}"}
          class="shrink-0"
          aria-label={@item.name}
        >
          <div class="w-[76px] h-[76px] rounded-xl overflow-hidden bg-surface-container-low">
            <img
              src={@item.image_url}
              alt={@item.name}
              class="w-full h-full object-cover"
              style={"view-transition-name: item-img-#{@item.id};"}
            />
          </div>
        </.link>

        <div class="flex-1 min-w-0">
          <.link navigate={~p"/menu/#{@org.slug}/item/#{@item.id}"} class="hover:opacity-80 transition-opacity">
            <h3 class="font-headline text-base font-bold leading-snug text-on-surface">
              {@item.name}
            </h3>
          </.link>
          <p
            :if={@item.description}
            class="text-sm text-on-surface-variant line-clamp-2 leading-relaxed mt-0.5"
          >
            {@item.description}
          </p>

          <div class="flex items-center justify-between mt-3">
            <span class="font-headline text-base font-bold text-primary">
              {price_label(@item)}
            </span>

            <.link
              :if={@customizable?}
              navigate={~p"/menu/#{@org.slug}/item/#{@item.id}"}
              class="flex items-center gap-1 bg-primary text-on-primary text-xs font-bold px-3.5 py-2 rounded-full hover:opacity-90 transition-opacity active:scale-95"
            >
              Customize
              <span class="material-symbols-outlined" style="font-size: 14px;">arrow_forward</span>
            </.link>

            <div :if={not @customizable?} class="flex items-center gap-1.5">
              <button
                :if={@qty > 0}
                phx-click="update_quantity"
                phx-value-item_id={@item.id}
                phx-value-delta="-1"
                class="w-8 h-8 rounded-full bg-surface-container flex items-center justify-center hover:bg-surface-container-high transition-colors active:scale-95"
                aria-label="Remove one"
              >
                <span class="material-symbols-outlined text-on-surface" style="font-size: 18px;">
                  remove
                </span>
              </button>
              <span :if={@qty > 0} class="min-w-[1.5rem] text-center text-sm font-bold text-on-surface">
                {@qty}
              </span>
              <button
                phx-click="update_quantity"
                phx-value-item_id={@item.id}
                phx-value-delta="1"
                class="w-8 h-8 rounded-full bg-primary text-on-primary flex items-center justify-center hover:opacity-90 transition-colors active:scale-95"
                aria-label="Add one"
              >
                <span class="material-symbols-outlined" style="font-size: 18px;">add</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp price_label(item) do
    cond do
      not Enum.empty?(item.sizes || []) ->
        min_price = item.sizes |> Enum.min_by(& &1.price.amount) |> then(& &1.price)
        "From #{format_money(min_price)}"

      item.price ->
        format_money(item.price)

      true ->
        "—"
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
