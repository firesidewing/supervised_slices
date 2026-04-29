defmodule SupervisedSlicesWeb.MenuLive.MenuComponent do
  use SupervisedSlicesWeb, :live_component

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <main class="bg-background min-h-screen pt-32 pb-32 px-4 max-w-2xl mx-auto">
      <section :for={category <- @categories} class="mb-16 last:mb-0">
        <div class="flex items-end justify-between mb-8 px-2">
          <h2 class="font-headline text-3xl font-bold tracking-tight text-on-surface">
            {category.name}
          </h2>
          <span class="font-label text-[0.65rem] uppercase tracking-[0.2em] text-outline mb-1"></span>
        </div>

        <div class="grid grid-cols-2 gap-x-4 gap-y-6">
          <%= for item <- category.menu_items do %>
            <.menu_item_card
              :if={customizable?(item)}
              item={item}
              cart_items_map={@cart_items_map}
              org={@org}
            />
            <.menu_item_row
              :if={!customizable?(item)}
              item={item}
              cart_items_map={@cart_items_map}
              org={@org}
              store_open={@store_open}
            />
          <% end %>
        </div>
      </section>

      <div :if={Enum.empty?(@categories)} class="text-center py-24 text-on-surface-variant">
        <span class="material-symbols-outlined text-6xl opacity-30">restaurant_menu</span>
        <p class="mt-4 text-lg font-medium">Menu coming soon</p>
      </div>
    </main>
    """
  end

  def menu_grid_preview(assigns) do
    ~H"""
    <div class="bg-surface min-h-full px-6 pt-16 pb-32">
      <div class="mb-10 px-2">
        <h2 class="font-headline text-3xl font-bold tracking-tight text-on-surface">{@category_name}</h2>
      </div>
      <div class="grid grid-cols-2 gap-x-4 gap-y-6">
        <%= for item <- @items do %>
          <div class="group flex flex-col bg-surface-container-lowest rounded-xl overflow-hidden shadow-soft hover:translate-y-[-4px] transition-all duration-300">
            <%= if item[:image_url] do %>
              <div class="aspect-square overflow-hidden relative">
                <img
                  src={item.image_url}
                  alt={item.name}
                  class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-110"
                />
              </div>
            <% else %>
              <div class="pt-8 px-6 pb-2">
                <div class="w-10 h-1 bg-primary/20 rounded-full mb-4" />
              </div>
            <% end %>
            <div class={["px-5 pb-5 flex flex-col flex-1 justify-between", item[:image_url] && "pt-4"]}>
              <div>
                <p class="font-headline font-bold text-base text-on-surface">{item.name}</p>
                <p class="text-xs text-on-surface-variant mt-2 opacity-80 leading-relaxed line-clamp-2">
                  {item.description}
                </p>
              </div>
              <div class="flex justify-between items-center mt-5">
                <span class="font-headline font-black text-on-surface">{item.price_display}</span>
                <span class="material-symbols-outlined text-on-surface-variant opacity-30">add_circle</span>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def basket_preview(assigns) do
    ~H"""
    <div class="bg-surface min-h-full text-on-surface">
      <div class="px-6 pt-12 pb-6">
        <p class="font-label text-[10px] uppercase tracking-widest opacity-40 mb-2">Review Order</p>
        <h2 class="font-headline text-4xl font-bold tracking-tight">Your Basket</h2>
      </div>

      <div class="px-6 space-y-4">
        <div class="bg-surface-container rounded-2xl p-5">
          <div class="flex justify-between items-start gap-4">
            <div class="flex-1">
              <p class="font-headline font-bold">{@item.name}</p>
              <div class="mt-1.5 space-y-0.5">
                <%= for size <- Enum.filter(@item.sizes, & &1.selected) do %>
                  <p class="text-xs text-on-surface-variant opacity-80">{size.name} · {size.label}</p>
                <% end %>
                <%= for group <- @item.modifier_groups do %>
                  <%= for mod <- Enum.filter(group.modifiers, & &1.selected) do %>
                    <p class="text-xs text-on-surface-variant opacity-80">+ {mod.name}</p>
                  <% end %>
                <% end %>
              </div>
            </div>
            <div class="flex flex-col items-end gap-2">
              <span class="font-headline font-black">{@item.total_display}</span>
              <div class="flex items-center gap-2">
                <div class="w-7 h-7 rounded-md bg-surface-container-high flex items-center justify-center">
                  <span class="material-symbols-outlined text-sm">remove</span>
                </div>
                <span class="font-bold text-sm">1</span>
                <div class="w-7 h-7 rounded-md bg-surface-container-high flex items-center justify-center">
                  <span class="material-symbols-outlined text-sm">add</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="px-1 space-y-3 pt-1">
          <div class="flex justify-between text-sm">
            <span class="font-label text-[10px] uppercase tracking-widest opacity-40">Subtotal</span>
            <span class="font-bold">{@item.total_display}</span>
          </div>
          <div class="w-full h-px bg-on-surface/5"></div>
          <div class="flex justify-between">
            <span class="font-label text-[10px] uppercase tracking-widest opacity-40">Total</span>
            <span class="font-headline font-black text-lg">{@item.total_display}</span>
          </div>
        </div>

        <div class="px-1 pt-2">
          <p class="font-label text-[10px] uppercase tracking-widest opacity-40 mb-3">Order Notes</p>
          <div class="border-b border-outline-variant pb-3">
            <p class="text-sm opacity-30 italic font-body">e.g. extra charred crust, no basil...</p>
          </div>
        </div>
      </div>

      <div class="mt-12 px-6 py-6 bg-surface/90 backdrop-blur-xl shadow-[0_-10px_40px_rgba(28,28,24,0.06)]">
        <div class="w-full py-4 bg-gradient-to-tr from-primary to-primary-container text-white font-label font-bold tracking-widest uppercase rounded-md shadow-lg text-center text-sm">
          Place Your Order · {@item.total_display}
        </div>
        <p class="text-center font-label text-[10px] opacity-30 uppercase tracking-widest mt-3">No account needed</p>
      </div>
    </div>
    """
  end

  defp menu_item_card(assigns) do
    qty = get_item_qty(assigns.cart_items_map, assigns.item.id)
    assigns = assign(assigns, qty: qty)

    ~H"""
    <.link
      patch={~p"/menu/#{@org.slug}/item/#{@item.id}"}
      phx-view-transition
      class="group flex flex-col bg-surface-container-lowest rounded-xl overflow-hidden transition-all duration-300 active:scale-[0.98] shadow-soft hover:translate-y-[-4px]"
    >
      <div :if={@item.images != []} class="aspect-square overflow-hidden relative">
        <img
          src={List.first(@item.images).url}
          alt={@item.name}
          class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-110"
          style={"view-transition-name: item-img-#{@item.id};"}
        />
        <div
          :if={@qty > 0}
          class="absolute top-3 right-3 w-8 h-8 bg-primary text-on-primary rounded-full flex items-center justify-center text-xs font-black shadow-lg animate-in zoom-in duration-300"
        >
          {@qty}
        </div>
      </div>

      <%!-- Intentional fallback for no image --%>
      <div :if={@item.images == []} class="pt-8 px-6 pb-2 relative">
        <div class="w-10 h-1 bg-primary/20 rounded-full mb-4" />
        <div
          :if={@qty > 0}
          class="absolute top-6 right-6 w-8 h-8 bg-primary text-on-primary rounded-full flex items-center justify-center text-xs font-black shadow-lg animate-in zoom-in duration-300"
        >
          {@qty}
        </div>
      </div>

      <div class="p-4 flex flex-col grow">
        <h3 class={[
          "font-headline font-bold leading-tight mb-1 text-on-surface group-hover:text-primary transition-colors",
          @item.images != [] && "text-lg",
          @item.images == [] && "text-xl"
        ]}>
          {@item.name}
        </h3>
        <p
          :if={@item.description}
          class="font-body text-xs text-on-surface-variant mb-4 grow line-clamp-2 leading-relaxed opacity-80"
        >
          {@item.description}
        </p>
        <div class="flex justify-between items-center mt-auto">
          <span class="font-label text-sm font-bold text-primary">
            {price_label(@item)}
          </span>
          <span class="material-symbols-outlined text-outline text-lg group-hover:translate-x-1 transition-transform">
            arrow_forward_ios
          </span>
        </div>
      </div>
    </.link>
    """
  end

  defp menu_item_row(assigns) do
    qty = get_item_qty(assigns.cart_items_map, assigns.item.id)
    assigns = assign(assigns, qty: qty)

    ~H"""
    <div class="col-span-2 flex items-center gap-4 bg-surface-container-low p-3 rounded-xl transition-all duration-300 hover:bg-surface-container group">
      <div :if={@item.images != []} class="w-20 h-20 rounded-lg overflow-hidden shrink-0 relative">
        <img
          src={List.first(@item.images).url}
          alt={@item.name}
          class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-110"
          style={"view-transition-name: item-img-#{@item.id};"}
        />
      </div>

      <div class="flex-1 min-w-0 py-1">
        <h3 class={[
          "font-headline font-bold truncate text-on-surface group-hover:text-primary transition-colors",
          @item.images != [] && "text-base",
          @item.images == [] && "text-lg"
        ]}>
          {@item.name}
        </h3>
        <p
          :if={@item.description}
          class="font-body text-[0.7rem] text-on-surface-variant truncate opacity-80"
        >
          {@item.description}
        </p>
        <span class="font-label text-sm font-bold text-primary mt-1 block">
          {format_money(@item.price)}
        </span>
      </div>

      <div class="flex items-center gap-3 bg-surface-container-lowest px-2 py-1.5 rounded-lg border border-outline-variant/20 shadow-sm transition-all group-hover:shadow-md group-hover:border-outline-variant/40">
        <button
          phx-click="update_quantity"
          phx-value-item_id={@item.id}
          phx-value-delta="-1"
          disabled={@qty == 0}
          class="w-7 h-7 flex items-center justify-center text-primary disabled:opacity-20 transition-all active:scale-90 hover:bg-primary/5 rounded-full"
          aria-label="Remove one"
        >
          <span class="material-symbols-outlined text-base font-black">remove</span>
        </button>
        <span class="font-label text-sm font-black w-4 text-center text-on-surface">
          {@qty}
        </span>
        <button
          phx-click="update_quantity"
          phx-value-item_id={@item.id}
          phx-value-delta="1"
          disabled={not @store_open}
          class="w-7 h-7 flex items-center justify-center text-on-primary-container bg-primary-container rounded-lg shadow-sm hover:bg-primary-container-high transition-all active:scale-90 disabled:opacity-20 disabled:grayscale"
          aria-label="Add one"
        >
          <span class="material-symbols-outlined text-base font-black">add</span>
        </button>
      </div>
    </div>
    """
  end

  defp customizable?(item) do
    not Enum.empty?(item.sizes || []) or not Enum.empty?(item.modifier_groups || [])
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
