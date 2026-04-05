defmodule SupervisedSlicesWeb.MenuLive.MenuComponent do
  use SupervisedSlicesWeb, :live_component

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <main class="pt-24 pb-36 px-4 max-w-5xl mx-auto">
      <section :for={{category, idx} <- Enum.with_index(@categories)} class="mb-12">
        <div class="flex items-center gap-3 mb-6">
          <div class={[
            "h-8 w-1 rounded-full shrink-0",
            if(rem(idx, 2) == 0, do: "bg-primary", else: "bg-secondary")
          ]}>
          </div>
          <h2
            class="text-2xl font-extrabold tracking-tight text-on-surface"
            style="font-family: 'Plus Jakarta Sans', sans-serif;"
          >
            {category.name}
          </h2>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
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
    assigns =
      assign(assigns,
        customizable?:
          not Enum.empty?(assigns.item.sizes || []) or
            not Enum.empty?(assigns.item.modifier_groups || [])
      )

    ~H"""
    <div class="bg-surface-container-lowest rounded-xl p-4 transition-all hover:scale-[1.01] hover:shadow-[0px_12px_32px_rgba(93,63,62,0.08)] flex flex-col gap-4">
      <.link navigate={~p"/menu/#{@org.slug}/item/#{@item.id}"} class="flex gap-4 group">
        <div class="relative w-24 h-24 shrink-0 overflow-hidden rounded-lg">
          <img
            src={@item.image_url || "https://placehold.co/96x96/f4f3f1/5d3f3e?text=🍕"}
            alt={@item.name}
            class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
            style={"view-transition-name: item-img-#{@item.id};"}
          />
        </div>
        <div class="flex-1 min-w-0">
          <h3
            class="text-base font-bold leading-snug mb-1 text-on-surface"
            style="font-family: 'Plus Jakarta Sans', sans-serif;"
          >
            {@item.name}
          </h3>
          <p class="text-sm text-on-surface-variant line-clamp-2 leading-relaxed">
            {@item.description}
          </p>
        </div>
      </.link>

      <div class="flex items-center justify-between py-1.5 px-3 rounded-lg bg-surface-container-low">
        <span class="text-sm font-bold text-primary">
          {cond do
            not Enum.empty?(@item.sizes || []) ->
              "From " <>
                format_money(
                  @item.sizes |> Enum.min_by(& &1.price.amount) |> then(& &1.price)
                )

            @item.price ->
              format_money(@item.price)

            true ->
              "—"
          end}
        </span>

        <.link
          :if={@customizable?}
          navigate={~p"/menu/#{@org.slug}/item/#{@item.id}"}
          class="flex items-center gap-1.5 bg-primary text-white text-xs font-bold px-4 py-2 rounded-full hover:opacity-90 transition-opacity"
        >
          Customize
          <span class="material-symbols-outlined" style="font-size: 14px;">arrow_forward</span>
        </.link>

        <div :if={!@customizable?} class="flex items-center bg-white rounded-full p-1 shadow-sm">
          <button
            phx-click="update_quantity"
            phx-value-item_id={@item.id}
            phx-value-delta="-1"
            class="w-7 h-7 flex items-center justify-center rounded-full hover:bg-surface-container transition-colors"
            aria-label="Remove one"
          >
            <span class="material-symbols-outlined" style="font-size: 18px;">remove</span>
          </button>
          <span class="px-2.5 text-sm font-bold min-w-[1.5rem] text-center">
            {get_item_qty(@cart_items_map, @item.id)}
          </span>
          <button
            phx-click="update_quantity"
            phx-value-item_id={@item.id}
            phx-value-delta="1"
            class="w-7 h-7 flex items-center justify-center rounded-full bg-primary text-white hover:bg-primary-container transition-colors"
            aria-label="Add one"
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

  defp get_item_qty(cart_items_map, item_id) do
    key = {to_string(item_id), nil, nil}
    get_in(cart_items_map, [key, :quantity]) || 0
  end
end
