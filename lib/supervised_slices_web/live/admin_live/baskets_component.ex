defmodule SupervisedSlicesWeb.AdminLive.BasketsComponent do
  use SupervisedSlicesWeb, :live_component

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="font-headline text-xl font-bold text-on-surface">
            Basket Monitor
          </h2>
          <p class="text-sm text-on-surface-variant mt-1">
            Real-time view of what customers have in their carts
          </p>
        </div>
        <div class="bg-primary text-white px-5 py-2 rounded-md text-sm font-bold uppercase tracking-wider">
          {length(@active_carts)} active
        </div>
      </div>

      <%= if Enum.empty?(@active_carts) do %>
        <div class="flex flex-col items-center py-24 text-on-surface-variant/20">
          <span class="material-symbols-outlined text-8xl">shopping_cart</span>
          <p class="mt-4 text-xl font-black font-headline uppercase tracking-widest opacity-40">
            No active baskets
          </p>
        </div>
      <% else %>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
          <%= for cart <- @active_carts do %>
            <div class="bg-surface-container-low rounded-md p-6 space-y-4 shadow-sm">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <span class="material-symbols-outlined text-primary text-lg">
                    shopping_bag
                  </span>
                  <span class="font-body text-xs font-black text-on-surface uppercase tracking-widest">
                    SESSION …{String.slice(cart.session_id || "anon", -6, 6)}
                  </span>
                </div>
                <span class="text-[0.65rem] font-bold uppercase tracking-widest text-on-surface-variant/60">
                  {time_ago(cart.inserted_at)}
                </span>
              </div>

              <div class="space-y-2">
                <%= for cart_item <- (cart.cart_items || []) do %>
                  <div class="flex items-center justify-between py-2 px-3 rounded bg-surface-container-high/50">
                    <span class="text-sm font-bold text-on-surface truncate">
                      {(cart_item.menu_item && cart_item.menu_item.name) || "Item"}
                    </span>
                    <span class="text-xs font-black text-primary ml-2 shrink-0">
                      {cart_item.quantity}x
                    </span>
                  </div>
                <% end %>

                <%= if Enum.empty?(cart.cart_items || []) do %>
                  <p class="text-[0.65rem] font-bold uppercase tracking-widest text-on-surface-variant/40 italic px-1">
                    Empty cart
                  </p>
                <% end %>
              </div>

              <div class="pt-4 border-t border-on-surface/5 flex justify-between items-center text-[0.65rem] font-bold uppercase tracking-widest text-on-surface-variant/60">
                <span>{length(cart.cart_items || [])} line items</span>
                <span class="text-on-surface font-black">
                  {(cart.cart_items || []) |> Enum.reduce(0, &(&1.quantity + &2))} items
                </span>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp time_ago(nil), do: ""

  defp time_ago(datetime) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      true -> "#{div(seconds, 3600)}h ago"
    end
  end
end
