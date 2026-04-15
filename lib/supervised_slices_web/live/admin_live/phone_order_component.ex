defmodule SupervisedSlicesWeb.AdminLive.PhoneOrderComponent do
  use SupervisedSlicesWeb, :live_component

  alias SupervisedSlices.Menu.Category
  alias SupervisedSlices.Orders.{Order, OrderItem, Emails}
  alias SupervisedSlices.PubSubNotifier

  # ---------------------------------------------------------------------------
  # Mount / Update
  # ---------------------------------------------------------------------------

  def mount(socket) do
    {:ok,
     socket
     |> assign(:categories, [])
     |> assign(:phone_cart, [])
     |> assign(:next_line_id, 0)
     |> assign(:configuring, nil)
     |> assign(:customer_name, "")
     |> assign(:customer_phone, "")
     |> assign(:customer_email, "")
     |> assign(:notes, "")
     |> assign(:placing, false)}
  end

  def update(%{show: true} = assigns, socket) do
    socket =
      socket
      |> assign(:show, true)
      |> assign(:org, assigns.org)
      |> assign(:ash_scope, assigns.ash_scope)

    socket =
      if socket.assigns.categories == [] do
        categories =
          Category.active!(
            scope: assigns.ash_scope,
            authorize?: false,
            load: [menu_items: [modifier_groups: [:modifiers], sizes: []]]
          )

        assign(socket, :categories, categories)
      else
        socket
      end

    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:show, assigns.show)
     |> assign(:org, assigns.org)
     |> assign(:ash_scope, assigns.ash_scope)}
  end

  # ---------------------------------------------------------------------------
  # Events — item configuration
  # ---------------------------------------------------------------------------

  def handle_event("configure_item", %{"id" => item_id}, socket) do
    item = find_item(socket.assigns.categories, item_id)

    if is_nil(item) do
      {:noreply, socket}
    else
      has_config = item.sizes != [] or item.modifier_groups != []

      if has_config do
        {:noreply,
         assign(socket,
           configuring: %{
             item: item,
             selected_size_id: nil,
             selected_modifier_ids: MapSet.new()
           }
         )}
      else
        {:noreply, add_to_cart(socket, item, nil, [])}
      end
    end
  end

  def handle_event("select_size", %{"id" => size_id}, socket) do
    {:noreply,
     update(socket, :configuring, &Map.put(&1, :selected_size_id, size_id))}
  end

  def handle_event("toggle_modifier", %{"id" => mod_id}, socket) do
    {:noreply,
     update(socket, :configuring, fn cfg ->
       ids = cfg.selected_modifier_ids

       new_ids =
         if MapSet.member?(ids, mod_id),
           do: MapSet.delete(ids, mod_id),
           else: MapSet.put(ids, mod_id)

       Map.put(cfg, :selected_modifier_ids, new_ids)
     end)}
  end

  def handle_event("add_configured", _params, socket) do
    %{configuring: cfg} = socket.assigns

    item = cfg.item
    size = find_size(item, cfg.selected_size_id)
    modifiers = find_modifiers(item, cfg.selected_modifier_ids)

    if item.sizes != [] and is_nil(size) do
      {:noreply, put_flash(socket, :error, "Please select a size.")}
    else
      {:noreply, socket |> add_to_cart(item, size, modifiers) |> assign(:configuring, nil)}
    end
  end

  def handle_event("cancel_configure", _params, socket) do
    {:noreply, assign(socket, :configuring, nil)}
  end

  # ---------------------------------------------------------------------------
  # Events — cart management
  # ---------------------------------------------------------------------------

  def handle_event("increment_line", %{"line_id" => line_id_str}, socket) do
    line_id = String.to_integer(line_id_str)

    phone_cart =
      Enum.map(socket.assigns.phone_cart, fn line ->
        if line.line_id == line_id, do: Map.update!(line, :quantity, &(&1 + 1)), else: line
      end)

    {:noreply, assign(socket, :phone_cart, phone_cart)}
  end

  def handle_event("decrement_line", %{"line_id" => line_id_str}, socket) do
    line_id = String.to_integer(line_id_str)

    phone_cart =
      socket.assigns.phone_cart
      |> Enum.map(fn line ->
        if line.line_id == line_id, do: Map.update!(line, :quantity, &(&1 - 1)), else: line
      end)
      |> Enum.reject(&(&1.quantity < 1))

    {:noreply, assign(socket, :phone_cart, phone_cart)}
  end

  def handle_event("remove_line", %{"line_id" => line_id_str}, socket) do
    line_id = String.to_integer(line_id_str)
    phone_cart = Enum.reject(socket.assigns.phone_cart, &(&1.line_id == line_id))
    {:noreply, assign(socket, :phone_cart, phone_cart)}
  end

  # ---------------------------------------------------------------------------
  # Events — customer form
  # ---------------------------------------------------------------------------

  def handle_event("update_field", %{"field" => field, "value" => value}, socket) do
    key = String.to_existing_atom(field)
    {:noreply, assign(socket, key, value)}
  end

  # ---------------------------------------------------------------------------
  # Events — place order + close
  # ---------------------------------------------------------------------------

  def handle_event("place_phone_order", _params, socket) do
    %{
      ash_scope: scope,
      org: org,
      phone_cart: phone_cart,
      customer_name: customer_name,
      customer_phone: customer_phone,
      customer_email: customer_email,
      notes: notes
    } = socket.assigns

    subtotal = cart_subtotal(phone_cart)
    tax_amount = calc_tax(subtotal, org.tax_rate)
    {:ok, total} = Money.add(subtotal, tax_amount)

    email_val = if customer_email == "", do: nil, else: customer_email
    notes_val = if notes == "", do: nil, else: notes

    order =
      Order.place_phone_order!(
        %{
          customer_name: customer_name,
          customer_phone: customer_phone,
          customer_email: email_val,
          notes: notes_val,
          total_price: total,
          tax_amount: tax_amount,
          delivery_type: :pickup,
          delivery_fee: Money.new!(0, total.currency)
        },
        scope: scope
      )

    Enum.each(phone_cart, fn line ->
      modifiers_snapshot =
        Enum.map(line.modifiers, fn mod ->
          %{
            "name" => mod.name,
            "price" => Money.to_string!(mod.price_delta || Money.new!(0, line.unit_price.currency))
          }
        end)

      size_snapshot =
        case line.size do
          %{name: name, price: p} -> %{"name" => name, "price" => Money.to_string!(p)}
          _ -> nil
        end

      OrderItem.create!(
        %{
          order_id: order.id,
          menu_item_id: line.menu_item.id,
          quantity: line.quantity,
          item_name: line.menu_item.name,
          price_at_time: line.unit_price,
          modifiers_snapshot: modifiers_snapshot,
          size_snapshot: size_snapshot
        },
        scope: scope
      )
    end)

    PubSubNotifier.broadcast_new_order(order)

    if email_val do
      Emails.send_order_confirmation(order)
    end

    send(self(), {:phone_order_placed})

    {:noreply,
     socket
     |> assign(:phone_cart, [])
     |> assign(:next_line_id, 0)
     |> assign(:configuring, nil)
     |> assign(:customer_name, "")
     |> assign(:customer_phone, "")
     |> assign(:customer_email, "")
     |> assign(:notes, "")
     |> assign(:placing, false)}
  end

  def handle_event("close", _params, socket) do
    send(self(), {:close_phone_order})
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <div
      id="phone-order-wrapper"
      class={[
        "fixed inset-0 z-50 transition-all duration-300",
        if(@show, do: "visible", else: "invisible pointer-events-none")
      ]}
    >
      <%!-- Backdrop --%>
      <div
        id="phone-order-backdrop"
        phx-click="close"
        phx-target={@myself}
        class={[
          "absolute inset-0 bg-on-surface/40 backdrop-blur-sm transition-opacity duration-300",
          if(@show, do: "opacity-100", else: "opacity-0")
        ]}
      >
      </div>

      <%!-- Panel --%>
      <div
        class={[
          "absolute inset-4 md:inset-8 lg:inset-12 bg-background rounded-md shadow-[0_40px_80px_-10px_rgba(28,28,24,0.25)] flex flex-col overflow-hidden transition-all duration-300",
          if(@show, do: "opacity-100 scale-100", else: "opacity-0 scale-95")
        ]}
      >
        <%!-- Header --%>
        <div class="flex items-center justify-between px-6 py-4 bg-surface-container-low shrink-0">
          <div>
            <p class="text-[10px] font-bold uppercase tracking-[0.2em] text-on-surface-variant/50">
              Kitchen
            </p>
            <h2 class="font-headline text-xl font-black text-on-surface tracking-tight">
              Phone Order
            </h2>
          </div>
          <button
            phx-click="close"
            phx-target={@myself}
            class="w-10 h-10 flex items-center justify-center rounded-md hover:bg-surface-container transition-colors text-on-surface-variant"
          >
            <span class="material-symbols-outlined !text-[20px]">close</span>
          </button>
        </div>

        <%!-- Body --%>
        <div class="flex flex-col md:flex-row flex-1 min-h-0">
          <%!-- Left: Menu Picker --%>
          <div class="flex-1 overflow-y-auto p-6 space-y-8 border-r border-on-surface/5">
            <p
              :if={@categories == []}
              class="text-on-surface-variant/40 text-sm font-bold uppercase tracking-widest"
            >
              Loading menu…
            </p>

            <div :for={cat <- @categories} :if={cat.menu_items != []} class="space-y-2">
              <h3 class="font-headline text-base font-black tracking-tight text-on-surface mb-3">
                {cat.name}
              </h3>

              <div :for={item <- cat.menu_items} :if={item.available} class="space-y-0">
                <div class="flex items-center justify-between py-3 px-4 rounded-md hover:bg-surface-container transition-colors group">
                  <div class="flex-1 min-w-0">
                    <p class="font-body font-bold text-sm text-on-surface truncate">{item.name}</p>
                    <p class="font-body text-xs text-on-surface-variant/60">
                      {base_price_string(item)}
                    </p>
                  </div>
                  <button
                    phx-click="configure_item"
                    phx-value-id={item.id}
                    phx-target={@myself}
                    class="ml-4 w-8 h-8 flex items-center justify-center rounded-md bg-primary text-white hover:opacity-90 active:scale-90 transition-all shrink-0"
                    aria-label={"Add #{item.name}"}
                  >
                    <span class="material-symbols-outlined !text-[18px] font-black">add</span>
                  </button>
                </div>
              </div>
            </div>
          </div>

          <%!-- Right: Summary + Customer Form --%>
          <div class="w-full md:w-96 shrink-0 flex flex-col overflow-y-auto bg-surface-container-low/30">
            <%!-- Cart summary --%>
            <div class="p-6 border-b border-on-surface/5 flex-shrink-0">
              <h3 class="font-headline text-sm font-black uppercase tracking-widest text-on-surface-variant/50 mb-4">
                Order
              </h3>

              <div
                :if={@phone_cart == []}
                class="text-on-surface-variant/30 text-xs font-bold uppercase tracking-widest py-4"
              >
                No items yet
              </div>

              <div class="space-y-3">
                <div :for={line <- @phone_cart} class="flex items-start gap-3">
                  <div class="flex items-center gap-1 shrink-0 mt-0.5">
                    <button
                      phx-click="decrement_line"
                      phx-value-line_id={line.line_id}
                      phx-target={@myself}
                      class="w-6 h-6 flex items-center justify-center rounded text-on-surface-variant/60 hover:bg-surface-container hover:text-on-surface transition-colors text-xs font-black"
                    >
                      −
                    </button>
                    <span class="w-5 text-center text-sm font-black text-on-surface">
                      {line.quantity}
                    </span>
                    <button
                      phx-click="increment_line"
                      phx-value-line_id={line.line_id}
                      phx-target={@myself}
                      class="w-6 h-6 flex items-center justify-center rounded text-on-surface-variant/60 hover:bg-surface-container hover:text-on-surface transition-colors text-xs font-black"
                    >
                      +
                    </button>
                  </div>
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-bold text-on-surface leading-tight">
                      {line.menu_item.name}
                      <span :if={line.size} class="font-normal text-on-surface-variant/70">
                        · {line.size.name}
                      </span>
                    </p>
                    <p :if={line.modifiers != []} class="text-[11px] text-on-surface-variant/50">
                      {Enum.map_join(line.modifiers, ", ", & &1.name)}
                    </p>
                  </div>
                  <div class="text-right shrink-0">
                    <p class="text-sm font-black text-on-surface">
                      {Money.to_string!(Money.mult!(line.unit_price, line.quantity))}
                    </p>
                    <button
                      phx-click="remove_line"
                      phx-value-line_id={line.line_id}
                      phx-target={@myself}
                      class="text-[10px] text-on-surface-variant/30 hover:text-error transition-colors uppercase font-bold tracking-wider"
                    >
                      remove
                    </button>
                  </div>
                </div>
              </div>

              <%!-- Totals --%>
              <div :if={@phone_cart != []} class="mt-4 pt-4 border-t border-on-surface/5 space-y-1">
                <div class="flex justify-between text-xs text-on-surface-variant/60 font-bold">
                  <span class="uppercase tracking-wider">Subtotal</span>
                  <span>{Money.to_string!(cart_subtotal(@phone_cart))}</span>
                </div>
                <div class="flex justify-between text-xs text-on-surface-variant/60 font-bold">
                  <span class="uppercase tracking-wider">Tax</span>
                  <span>{Money.to_string!(calc_tax(cart_subtotal(@phone_cart), @org.tax_rate))}</span>
                </div>
                <div class="flex justify-between text-base font-black text-on-surface mt-2">
                  <span class="uppercase tracking-tight">Total</span>
                  <span>
                    {Money.to_string!(
                      elem(
                        Money.add(
                          cart_subtotal(@phone_cart),
                          calc_tax(cart_subtotal(@phone_cart), @org.tax_rate)
                        ),
                        1
                      )
                    )}
                  </span>
                </div>
              </div>
            </div>

            <%!-- Customer form --%>
            <div class="p-6 space-y-4 flex-1">
              <h3 class="font-headline text-sm font-black uppercase tracking-widest text-on-surface-variant/50">
                Customer
              </h3>

              <div class="space-y-4">
                <div>
                  <label class="block text-[10px] uppercase font-bold tracking-[0.15em] text-on-surface-variant/60 mb-1">
                    Name <span class="text-primary">*</span>
                  </label>
                  <input
                    type="text"
                    value={@customer_name}
                    phx-blur="update_field"
                    phx-value-field="customer_name"
                    phx-target={@myself}
                    placeholder="Customer name"
                    class="w-full bg-transparent border-b border-outline-variant/20 focus:border-primary py-2 text-sm font-body text-on-surface placeholder:text-on-surface-variant/30 outline-none transition-colors"
                  />
                </div>

                <div>
                  <label class="block text-[10px] uppercase font-bold tracking-[0.15em] text-on-surface-variant/60 mb-1">
                    Phone <span class="text-primary">*</span>
                  </label>
                  <input
                    type="tel"
                    value={@customer_phone}
                    phx-blur="update_field"
                    phx-value-field="customer_phone"
                    phx-target={@myself}
                    placeholder="Customer phone"
                    class="w-full bg-transparent border-b border-outline-variant/20 focus:border-primary py-2 text-sm font-body text-on-surface placeholder:text-on-surface-variant/30 outline-none transition-colors"
                  />
                </div>

                <div>
                  <label class="block text-[10px] uppercase font-bold tracking-[0.15em] text-on-surface-variant/60 mb-1">
                    Email <span class="text-on-surface-variant/40 normal-case font-normal">(optional)</span>
                  </label>
                  <input
                    type="email"
                    value={@customer_email}
                    phx-blur="update_field"
                    phx-value-field="customer_email"
                    phx-target={@myself}
                    placeholder="Confirmation email"
                    class="w-full bg-transparent border-b border-outline-variant/20 focus:border-primary py-2 text-sm font-body text-on-surface placeholder:text-on-surface-variant/30 outline-none transition-colors"
                  />
                </div>

                <div>
                  <label class="block text-[10px] uppercase font-bold tracking-[0.15em] text-on-surface-variant/60 mb-1">
                    Notes <span class="text-on-surface-variant/40 normal-case font-normal">(optional)</span>
                  </label>
                  <textarea
                    phx-blur="update_field"
                    phx-value-field="notes"
                    phx-target={@myself}
                    placeholder="Any special requests…"
                    rows="2"
                    class="w-full bg-transparent border-b border-outline-variant/20 focus:border-primary py-2 text-sm font-body text-on-surface placeholder:text-on-surface-variant/30 outline-none transition-colors resize-none"
                  >{@notes}</textarea>
                </div>
              </div>

              <button
                phx-click="place_phone_order"
                phx-target={@myself}
                disabled={@phone_cart == [] or String.trim(@customer_name) == "" or String.trim(@customer_phone) == "" or @placing}
                class="w-full mt-6 py-4 rounded-md font-bold text-sm uppercase tracking-[0.1em] bg-gradient-to-br from-primary to-primary-container text-on-primary transition-all active:scale-[0.98] disabled:opacity-40 disabled:cursor-not-allowed hover:opacity-95"
              >
                Place Phone Order
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Item Configurator Modal --%>
      <div
        :if={@configuring}
        class="absolute inset-0 z-10 flex items-center justify-center p-6"
        phx-key="Escape"
        phx-window-keydown="cancel_configure"
        phx-target={@myself}
      >
        <div
          phx-click="cancel_configure"
          phx-target={@myself}
          class="absolute inset-0 bg-on-surface/20"
        >
        </div>
        <div class="relative bg-background rounded-md shadow-[0_40px_60px_-10px_rgba(28,28,24,0.2)] w-full max-w-md p-6 space-y-6">
          <div class="flex items-start justify-between">
            <div>
              <h3 class="font-headline text-lg font-black text-on-surface">
                {@configuring.item.name}
              </h3>
              <p class="text-xs text-on-surface-variant/60 font-bold">
                {base_price_string(@configuring.item)}
              </p>
            </div>
            <button
              phx-click="cancel_configure"
              phx-target={@myself}
              class="text-on-surface-variant/40 hover:text-on-surface transition-colors"
            >
              <span class="material-symbols-outlined !text-[20px]">close</span>
            </button>
          </div>

          <%!-- Size picker --%>
          <div :if={@configuring.item.sizes != []} class="space-y-3">
            <h4 class="text-[10px] font-bold uppercase tracking-[0.15em] text-on-surface-variant/60">
              Size <span class="text-primary">*</span>
            </h4>
            <div class="grid grid-cols-2 gap-2">
              <button
                :for={size <- @configuring.item.sizes}
                phx-click="select_size"
                phx-value-id={size.id}
                phx-target={@myself}
                class={[
                  "py-3 px-4 rounded-md text-left transition-all",
                  if(to_string(@configuring.selected_size_id) == to_string(size.id),
                    do: "bg-primary text-on-primary",
                    else: "bg-surface-container hover:bg-surface-container-high text-on-surface"
                  )
                ]}
              >
                <p class="text-xs font-black uppercase tracking-wide">{size.name}</p>
                <p class="text-[11px] font-bold opacity-70">{Money.to_string!(size.price)}</p>
              </button>
            </div>
          </div>

          <%!-- Modifier groups --%>
          <div :for={group <- @configuring.item.modifier_groups} class="space-y-3">
            <h4 class="text-[10px] font-bold uppercase tracking-[0.15em] text-on-surface-variant/60">
              {group.name}
            </h4>
            <div class="space-y-1">
              <button
                :for={mod <- group.modifiers}
                phx-click="toggle_modifier"
                phx-value-id={mod.id}
                phx-target={@myself}
                class={[
                  "w-full flex items-center justify-between py-2.5 px-4 rounded-md text-left transition-all",
                  if(MapSet.member?(@configuring.selected_modifier_ids, to_string(mod.id)),
                    do: "bg-secondary-container text-on-secondary-container",
                    else: "bg-surface-container hover:bg-surface-container-high text-on-surface"
                  )
                ]}
              >
                <span class="text-sm font-bold">{mod.name}</span>
                <span :if={mod.price_delta} class="text-xs font-bold opacity-70">
                  +{Money.to_string!(mod.price_delta)}
                </span>
              </button>
            </div>
          </div>

          <button
            phx-click="add_configured"
            phx-target={@myself}
            class="w-full py-3 rounded-md font-bold text-sm uppercase tracking-[0.1em] bg-gradient-to-br from-primary to-primary-container text-on-primary hover:opacity-95 active:scale-[0.98] transition-all"
          >
            Add to Order
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp add_to_cart(socket, item, size, modifiers) do
    unit_price = item_price(item, size, modifiers)
    cart = socket.assigns.phone_cart
    line_id = socket.assigns.next_line_id

    # Try to find existing matching line
    match_idx =
      Enum.find_index(cart, fn line ->
        line.menu_item.id == item.id and
          same_size?(line.size, size) and
          same_modifiers?(line.modifiers, modifiers)
      end)

    new_cart =
      if match_idx do
        List.update_at(cart, match_idx, &Map.update!(&1, :quantity, fn q -> q + 1 end))
      else
        cart ++
          [
            %{
              line_id: line_id,
              menu_item: item,
              size: size,
              modifiers: modifiers,
              quantity: 1,
              unit_price: unit_price
            }
          ]
      end

    socket
    |> assign(:phone_cart, new_cart)
    |> assign(:next_line_id, line_id + 1)
  end

  defp item_price(item, nil, modifiers), do: item_price(item, nil, modifiers, item.price)

  defp item_price(item, size, modifiers),
    do: item_price(item, size, modifiers, size.price)

  defp item_price(_item, _size, modifiers, base) do
    Enum.reduce(modifiers, base, fn mod, acc ->
      if mod.price_delta do
        case Money.add(acc, mod.price_delta) do
          {:ok, p} -> p
          _ -> acc
        end
      else
        acc
      end
    end)
  end

  defp cart_subtotal([]), do: Money.new!(0, :USD)

  defp cart_subtotal(phone_cart) do
    Enum.reduce(phone_cart, nil, fn line, acc ->
      line_total = Money.mult!(line.unit_price, line.quantity)
      if is_nil(acc), do: line_total, else: elem(Money.add(acc, line_total), 1)
    end)
  end

  defp calc_tax(subtotal, tax_rate) do
    if Decimal.compare(tax_rate, Decimal.new("0")) == :gt do
      Money.mult!(subtotal, tax_rate)
    else
      Money.new!(0, subtotal.currency)
    end
  end

  defp find_item(categories, item_id) do
    Enum.find_value(categories, fn cat ->
      Enum.find(cat.menu_items, &(to_string(&1.id) == to_string(item_id)))
    end)
  end

  defp find_size(_item, nil), do: nil

  defp find_size(item, size_id) do
    Enum.find(item.sizes, &(to_string(&1.id) == to_string(size_id)))
  end

  defp find_modifiers(item, modifier_id_set) do
    Enum.flat_map(item.modifier_groups, fn group ->
      Enum.filter(group.modifiers, &MapSet.member?(modifier_id_set, to_string(&1.id)))
    end)
  end

  defp same_size?(nil, nil), do: true
  defp same_size?(%{id: a}, %{id: b}), do: a == b
  defp same_size?(_, _), do: false

  defp same_modifiers?(a, b) do
    MapSet.new(Enum.map(a, & &1.id)) == MapSet.new(Enum.map(b, & &1.id))
  end

  defp base_price_string(item) do
    case item.sizes do
      [] -> Money.to_string!(item.price)
      [first | _] -> "from #{Money.to_string!(first.price)}"
    end
  end
end
