defmodule SupervisedSlicesWeb.AdminLive.BasketsComponent do
  use SupervisedSlicesWeb, :live_component

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <section class="p-8 space-y-8">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="font-headline text-xl font-bold text-on-surface">
            Active Baskets
          </h2>
          <p class="text-sm text-on-surface-variant mt-1">
            Real-time view of what customers have in their carts
          </p>
        </div>
        <div class="bg-primary-fixed text-on-primary-fixed-variant px-5 py-2 rounded-full text-sm font-bold">
          {length(@active_carts)} active
        </div>
      </div>

      <%= if Enum.empty?(@active_carts) do %>
        <div class="flex flex-col items-center py-20 text-on-surface-variant">
          <span class="material-symbols-outlined text-6xl opacity-30">shopping_cart</span>
          <p class="mt-4 text-lg font-medium">No active baskets</p>
          <p class="text-sm opacity-60 mt-1">Customer carts will appear here in real-time</p>
        </div>
      <% else %>
        <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          <%= for cart <- @active_carts do %>
            <div class="bg-surface-container-lowest rounded-xl p-5 space-y-4">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <span class="material-symbols-outlined text-on-surface-variant text-lg">
                    shopping_bag
                  </span>
                  <span class="font-body text-xs font-bold text-on-surface-variant uppercase tracking-wider">
                    Session …{String.slice(cart.session_id || "anon", -6, 6)}
                  </span>
                </div>
                <span class="text-xs text-on-surface-variant">{time_ago(cart.inserted_at)}</span>
              </div>

              <div class="space-y-2">
                <%= for cart_item <- (cart.cart_items || []) do %>
                  <div class="flex items-center justify-between py-1.5 px-3 rounded-lg bg-surface-container-low">
                    <span class="text-sm font-medium text-on-surface truncate">
                      {(cart_item.menu_item && cart_item.menu_item.name) || "Item"}
                    </span>
                    <span class="text-xs font-bold text-primary ml-2 shrink-0">
                      ×{cart_item.quantity}
                    </span>
                  </div>
                <% end %>

                <%= if Enum.empty?(cart.cart_items || []) do %>
                  <p class="text-xs text-on-surface-variant italic px-1">Empty cart</p>
                <% end %>
              </div>

              <div class="pt-1 border-t border-surface-container-low flex justify-between text-xs text-on-surface-variant">
                <span>{length(cart.cart_items || [])} line items</span>
                <span class="font-bold text-on-surface">
                  {(cart.cart_items || []) |> Enum.reduce(0, &(&1.quantity + &2))} total items
                </span>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </section>
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
