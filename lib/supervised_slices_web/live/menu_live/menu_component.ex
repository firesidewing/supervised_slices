defmodule SupervisedSlicesWeb.MenuLive.MenuComponent do
  use SupervisedSlicesWeb, :live_component

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <main class="bg-background min-h-screen pt-28 pb-28 px-4 max-w-2xl mx-auto">
      <section :for={category <- @categories} class="mb-12 last:mb-0">
        <div class="flex flex-col gap-1 mb-6 px-2">
          <h2 class="font-headline text-3xl font-black tracking-tighter text-on-surface uppercase italic">
            {category.name}
          </h2>
        </div>

        <div class="grid grid-cols-1 gap-4">
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
      "bg-surface-container-lowest rounded-xl p-5 transition-all duration-300",
      "shadow-[0px_12px_32px_rgba(93,63,62,0.08)] hover:shadow-[0px_16px_48px_rgba(93,63,62,0.12)]",
      "hover:scale-[1.02] active:scale-[0.98] group"
    ]}>
      <div class="flex gap-5 items-start">
        <.link
          :if={@item.image_url}
          navigate={~p"/menu/#{@org.slug}/item/#{@item.id}"}
          class="shrink-0 relative overflow-visible"
          aria-label={@item.name}
        >
          <div class="w-24 h-24 rounded-lg overflow-hidden bg-surface-container-low shadow-inner">
            <img
              src={@item.image_url}
              alt={@item.name}
              class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-110"
              style={"view-transition-name: item-img-#{@item.id};"}
            />
          </div>
          <div :if={@qty > 0} class="absolute -top-2 -right-2 w-7 h-7 bg-primary text-on-primary rounded-full flex items-center justify-center text-xs font-black shadow-lg animate-in zoom-in duration-300">
            {@qty}
          </div>
        </.link>

        <div class="flex-1 min-w-0 py-1">
          <div class="flex justify-between items-start gap-2">
            <.link navigate={~p"/menu/#{@org.slug}/item/#{@item.id}"} class="block group/title">
              <h3 class="font-headline text-lg font-black leading-tight text-on-surface group-hover/title:text-primary transition-colors">
                {@item.name}
              </h3>
            </.link>
            <span class="font-headline text-base font-black text-primary shrink-0">
              {price_label(@item)}
            </span>
          </div>
          
          <p
            :if={@item.description}
            class="text-sm text-on-surface-variant line-clamp-2 leading-relaxed mt-2 font-medium opacity-80"
          >
            {@item.description}
          </p>

          <div class="flex items-center justify-end mt-4">
            <.link
              :if={@customizable?}
              id={"customize-#{@item.id}"}
              navigate={~p"/menu/#{@org.slug}/item/#{@item.id}"}
              phx-click={JS.add_class("opacity-40 scale-95", to: "#customize-#{@item.id}") |> JS.add_class("cursor-wait", to: "body")}
              class="flex items-center gap-2 bg-gradient-to-r from-primary to-primary-container text-on-primary text-xs font-black px-5 py-2.5 rounded-lg hover:shadow-lg hover:shadow-primary/20 transition-all active:scale-95"
            >
              CUSTOMIZE
              <span class="material-symbols-outlined !text-[16px]">arrow_forward</span>
            </.link>

            <div :if={not @customizable?} class="flex items-center gap-3">
              <button
                :if={@qty > 0}
                phx-click="update_quantity"
                phx-value-item_id={@item.id}
                phx-value-delta="-1"
                class="w-9 h-9 rounded-full bg-surface-container flex items-center justify-center hover:bg-surface-container-high transition-all active:scale-90 [&.phx-click-loading]:opacity-50 [&.phx-click-loading]:cursor-wait"
                aria-label="Remove one"
              >
                <span class="material-symbols-outlined text-on-surface [.phx-click-loading]:hidden" style="font-size: 20px;">
                  remove
                </span>
                <svg class="animate-spin h-4 w-4 text-on-surface hidden [.phx-click-loading]:block" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
              </button>
              
              <button
                phx-click="update_quantity"
                phx-value-item_id={@item.id}
                phx-value-delta="1"
                class="w-9 h-9 rounded-full bg-gradient-to-r from-primary to-primary-container text-on-primary flex items-center justify-center hover:shadow-lg hover:shadow-primary/20 transition-all active:scale-90 [&.phx-click-loading]:opacity-50 [&.phx-click-loading]:cursor-wait"
                aria-label="Add one"
              >
                <span class="material-symbols-outlined [.phx-click-loading]:hidden" style="font-size: 20px;">add</span>
                <svg class="animate-spin h-4 w-4 text-on-primary hidden [.phx-click-loading]:block" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
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
