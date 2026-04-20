defmodule SupervisedSlicesWeb.MenuLive.ItemComponent do
  use SupervisedSlicesWeb, :live_component

  def update(%{selected_item: new_item} = assigns, socket) do
    current_item_id = socket.assigns[:selected_item] && socket.assigns.selected_item.id
    needs_init = is_nil(current_item_id) or current_item_id != new_item.id

    socket = assign(socket, assigns)

    socket =
      if needs_init do
        default_size_id =
          case new_item.sizes || [] do
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

  def handle_event(
        "toggle_modifier",
        %{"modifier_id" => modifier_id, "group_id" => group_id, "max_selections" => max_sel_str},
        socket
      ) do
    item = socket.assigns.selected_item
    group = Enum.find(item.modifier_groups || [], &(to_string(&1.id) == group_id))
    max_selections = if max_sel_str != "", do: String.to_integer(max_sel_str)
    mods = socket.assigns.selected_modifiers

    new_mods =
      if MapSet.member?(mods, modifier_id) do
        MapSet.delete(mods, modifier_id)
      else
        base =
          if max_selections == 1 and group do
            group_ids = group.modifiers |> Enum.map(&to_string(&1.id)) |> MapSet.new()
            MapSet.difference(mods, group_ids)
          else
            mods
          end

        MapSet.put(base, modifier_id)
      end

    {:noreply, assign(socket, :selected_modifiers, new_mods)}
  end

  def render(assigns) do
    item = assigns.selected_item
    selected_size_id = assigns[:selected_size_id]
    selected_modifiers = assigns[:selected_modifiers] || MapSet.new()
    has_customization = not Enum.empty?(item.sizes || []) or not Enum.empty?(item.modifier_groups)

    can_add =
      Enum.all?(item.modifier_groups || [], fn group ->
        selected_count =
          Enum.count(group.modifiers || [], fn m ->
            MapSet.member?(selected_modifiers, to_string(m.id))
          end)

        min = group.min_selections || 0
        not (group.required and selected_count < max(min, 1))
      end)

    assigns =
      assign(assigns,
        has_customization: has_customization,
        total_price: compute_total(item, selected_size_id, selected_modifiers),
        can_add_to_cart: can_add
      )

    ~H"""
    <div class="bg-surface min-h-screen text-on-surface antialiased">
      <main class="pt-[72px] pb-44">
        <!-- Hero Section -->
        <div
          :if={all_images(@selected_item) != []}
          class="relative w-full aspect-[4/5] md:aspect-video overflow-hidden"
        >
          <div
            id={"carousel-#{@selected_item.id}"}
            phx-hook="Carousel"
            class="flex h-full overflow-x-auto snap-x snap-mandatory scrollbar-hide"
          >
            <div
              :for={{url, idx} <- Enum.with_index(all_images(@selected_item))}
              id={"slide-#{@selected_item.id}-#{idx}"}
              class="snap-center shrink-0 w-full h-full"
            >
              <img
                src={url}
                alt={@selected_item.name}
                class="w-full h-full object-cover"
                style={
                  if idx == 0, do: "view-transition-name: item-img-#{@selected_item.id};", else: ""
                }
              />
            </div>
          </div>
          <div
            :if={length(all_images(@selected_item)) > 1}
            id={"carousel-dots-#{@selected_item.id}"}
            class="absolute bottom-20 left-0 right-0 flex justify-center gap-1.5 z-10 pointer-events-none"
          />
          <div class="absolute bottom-0 left-0 w-full h-2/3 bg-gradient-to-t from-surface to-transparent pointer-events-none" />
          <!-- Headline Overlay -->
          <div class="absolute bottom-8 left-8 right-8">
            <div class="flex items-center gap-2 mb-2">
              <span class="bg-secondary-container text-on-secondary-container text-[10px] px-2 py-0.5 rounded-full font-label tracking-widest uppercase font-bold">
                Chef's Signature
              </span>
            </div>
            <h2 class="font-headline text-4xl md:text-5xl font-bold tracking-tight text-on-surface leading-none">
              {@selected_item.name}
            </h2>
            <p class="mt-2 text-on-surface-variant max-w-xl text-sm md:text-base italic opacity-90">
              {@selected_item.description}
            </p>
          </div>
        </div>

        <%!-- Fallback for no image --%>
        <div :if={all_images(@selected_item) == []} class="px-8 pt-12 pb-6 max-w-3xl mx-auto">
          <div class="flex items-center gap-2 mb-4"></div>
          <h2 class="font-headline text-5xl md:text-6xl font-bold tracking-tight text-on-surface leading-tight">
            {@selected_item.name}
          </h2>
          <p class="mt-6 text-on-surface-variant max-w-2xl text-base md:text-lg italic opacity-90 leading-relaxed">
            {@selected_item.description}
          </p>
          <div class="w-24 h-1 bg-primary/20 rounded-full mt-10" />
        </div>

        <div class={[
          "px-8 space-y-12 max-w-3xl mx-auto relative z-10",
          @selected_item.images != [] && "-mt-4",
          @selected_item.images == [] && "mt-8"
        ]}>
          <!-- Size Selector Section -->
          <section :if={not Enum.empty?(@selected_item.sizes || [])}>
            <div class="flex items-baseline justify-between mb-6">
              <h3 class="font-headline text-xl font-bold">Select Diameter</h3>
              <span class="font-label text-xs tracking-widest uppercase opacity-60">
                Essential Scale
              </span>
            </div>
            <div class="flex overflow-x-auto gap-4 pb-4 no-scrollbar">
              <.size_card
                :for={size <- @selected_item.sizes || []}
                size={size}
                selected={to_string(size.id) == @selected_size_id}
                myself={@myself}
              />
            </div>
          </section>
          
    <!-- Modifier Groups -->
          <section :for={group <- @selected_item.modifier_groups} class="space-y-6">
            <div class="flex items-baseline justify-between">
              <div class="flex items-center gap-3">
                <h3 class="font-headline text-xl font-bold">{group.name}</h3>
                <span
                  :if={group.required}
                  class="text-[10px] font-bold uppercase tracking-widest text-error opacity-80"
                >
                  Required
                </span>
              </div>
              <span class="font-label text-xs tracking-widest uppercase opacity-60">
                {cond do
                  group.max_selections == 1 -> "Pick one"
                  group.max_selections -> "Pick up to #{group.max_selections}"
                  true -> "Optional Palette"
                end}
              </span>
            </div>
            <div class="grid grid-cols-1 gap-3">
              <.modifier_card
                :for={modifier <- group.modifiers}
                modifier={modifier}
                group={group}
                selected={MapSet.member?(@selected_modifiers, to_string(modifier.id))}
                selected_size_id={@selected_size_id}
                group_selected_count={
                  Enum.count(group.modifiers, fn m ->
                    MapSet.member?(@selected_modifiers, to_string(m.id))
                  end)
                }
                myself={@myself}
              />
            </div>
          </section>
          
    <!-- Preparation Notes (Mock) -->
          <section>
            <div class="flex items-baseline justify-between mb-6">
              <h3 class="font-headline text-xl font-bold">Preparation Notes</h3>
            </div>
            <textarea
              class="w-full bg-transparent border-none border-b border-outline-variant focus:border-primary focus:ring-0 text-sm py-4 px-0 placeholder:opacity-40 min-h-[100px] font-body"
              placeholder="e.g. Extra charred crust, no basil..."
            ></textarea>
          </section>
        </div>
      </main>
      
    <!-- Sticky Footer Action -->
      <footer class="fixed bottom-0 left-0 w-full bg-surface/90 backdrop-blur-xl px-8 py-6 z-50 shadow-[0_-10px_40px_rgba(28,28,24,0.06)]">
        <div class="max-w-3xl mx-auto flex items-center justify-between gap-6">
          <div class="flex flex-col">
            <span class="font-label text-[10px] tracking-widest uppercase opacity-60">
              Total Value
            </span>
            <span :if={@total_price} class="font-headline text-2xl font-black text-on-surface">
              {format_money(@total_price)}
            </span>
          </div>
          <button
            phx-click="add_to_cart"
            phx-value-item_id={@selected_item.id}
            phx-value-size_id={@selected_size_id}
            phx-value-modifier_ids={Enum.join(MapSet.to_list(@selected_modifiers), ",")}
            disabled={not @store_open or not @can_add_to_cart}
            class="flex-1 py-4 bg-gradient-to-tr from-primary to-primary-container text-white font-label font-bold tracking-widest uppercase rounded-md shadow-lg scale-100 active:scale-95 transition-all phx-click-loading:opacity-75 phx-click-loading:scale-95 phx-click-loading:cursor-wait phx-click-loading:pointer-events-none disabled:opacity-40 disabled:grayscale disabled:cursor-not-allowed"
            style="view-transition-name: basket;"
          >
            <span class="phx-click-loading:hidden">
              {if @can_add_to_cart, do: "Add to Basket", else: "Select required options"}
            </span>
            <span class="hidden phx-click-loading:inline">Adding...</span>
          </button>
        </div>
      </footer>
    </div>
    """
  end

  defp size_card(assigns) do
    ~H"""
    <button
      id={"size-#{@size.id}"}
      phx-click={JS.push("select_size")}
      phx-value-size_id={@size.id}
      phx-target={@myself}
      class={[
        "flex-shrink-0 w-28 h-36 flex flex-col items-center justify-center rounded-xl transition-all duration-300",
        if(@selected,
          do: "bg-surface-container border-b-2 border-primary-container shadow-md",
          else: "bg-surface-container-low opacity-80 hover:opacity-100 hover:bg-surface-container"
        )
      ]}
    >
      <span class="font-headline text-lg font-bold">{@size.name}</span>
      <span class="text-[10px] opacity-60 mt-1 font-label uppercase tracking-widest">
        {size_subtitle(@size)}
      </span>
      <span class={[
        "font-bold mt-4",
        if(@selected, do: "text-primary", else: "text-on-surface")
      ]}>
        {format_money(@size.price)}
      </span>
    </button>
    """
  end

  defp size_subtitle(size) do
    case size.name do
      "Personal" -> "Personal"
      "Small" -> "Small"
      "Medium" -> "Medium"
      "Large" -> "Large"
      "Atelier" -> "Atelier"
      _ -> "Portion"
    end
  end

  defp modifier_card(assigns) do
    max = assigns.group.max_selections
    at_max = is_integer(max) and assigns.group_selected_count >= max and not assigns.selected

    assigns = assign(assigns, at_max: at_max)

    ~H"""
    <button
      id={"modifier-#{@modifier.id}"}
      phx-click={JS.push("toggle_modifier")}
      phx-value-modifier_id={@modifier.id}
      phx-value-group_id={@group.id}
      phx-value-max_selections={@group.max_selections || ""}
      phx-target={@myself}
      disabled={@at_max}
      class={[
        "group flex items-center justify-between p-4 rounded-xl transition-all duration-300 text-left w-full",
        if(@selected,
          do: "bg-surface-container shadow-sm border-b-2 border-primary-container",
          else: "bg-surface-container-low hover:bg-surface-container opacity-80 hover:opacity-100"
        ),
        if(@at_max, do: "opacity-30 cursor-not-allowed")
      ]}
    >
      <div class="flex items-center gap-4">
        <span class={[
          "material-symbols-outlined transition-colors",
          if(@selected, do: "text-primary", else: "opacity-40")
        ]}>
          {modifier_icon(@modifier)}
        </span>
        <div>
          <p class="font-bold text-sm">{@modifier.name}</p>
          <p
            :if={effective_price_delta(@modifier, @selected_size_id)}
            class="text-xs opacity-60"
          >
            +{format_money(effective_price_delta(@modifier, @selected_size_id))}
          </p>
        </div>
      </div>

      <div class="flex items-center gap-3">
        <div
          :if={@group.max_selections == 1}
          class={[
            "w-5 h-5 rounded-full border border-outline-variant flex items-center justify-center transition-all",
            if(@selected, do: "bg-primary border-primary", else: "")
          ]}
        >
          <div :if={@selected} class="w-1.5 h-1.5 rounded-full bg-white" />
        </div>

        <div
          :if={@group.max_selections != 1}
          class={[
            "w-8 h-8 flex items-center justify-center rounded transition-all",
            if(@selected,
              do: "bg-primary text-white border-b-2 border-primary-container scale-95",
              else:
                "bg-surface-container-low text-on-surface opacity-40 border-b-2 border-outline-variant"
            )
          ]}
        >
          <span class="material-symbols-outlined text-sm">
            {if(@selected, do: "check", else: "add")}
          </span>
        </div>
      </div>
    </button>
    """
  end

  defp effective_price_delta(modifier, nil), do: modifier.price_delta

  defp effective_price_delta(modifier, size_id) do
    size_price =
      Enum.find(modifier.size_prices || [], fn sp ->
        to_string(sp.size_id) == size_id
      end)

    case size_price do
      %{price_delta: delta} -> delta
      _ -> modifier.price_delta
    end
  end

  defp modifier_icon(modifier) do
    name = String.downcase(modifier.name)

    cond do
      String.contains?(name, "cheese") -> "egg"
      String.contains?(name, "tomato") -> "nutrition"
      String.contains?(name, "basil") -> "spa"
      String.contains?(name, "oil") -> "water_drop"
      String.contains?(name, "dough") or String.contains?(name, "crust") -> "bakery_dining"
      String.contains?(name, "meat") or String.contains?(name, "prosciutto") -> "flatware"
      true -> "add_circle"
    end
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
          delta = effective_price_delta(modifier, selected_size_id)

          if MapSet.member?(selected_modifiers, to_string(modifier.id)) && delta do
            case Money.add(inner_acc, delta) do
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

  defp format_money(money) do
    Money.to_string!(money)
  rescue
    _ -> "#{money}"
  end

  defp all_images(item) do
    imgs =
      case item.images do
        %Ash.NotLoaded{} -> []
        images -> images |> Enum.sort_by(& &1.position) |> Enum.map(& &1.url)
      end

    imgs
  end
end
