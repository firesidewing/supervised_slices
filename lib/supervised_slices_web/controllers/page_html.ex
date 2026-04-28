defmodule SupervisedSlicesWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use SupervisedSlicesWeb, :html

  import SupervisedSlicesWeb.AdminLive.OrdersComponent, only: [order_preview: 1]
  import SupervisedSlicesWeb.MenuLive.ItemComponent, only: [item_detail_preview: 1]
  import SupervisedSlicesWeb.MenuLive.MenuComponent, only: [menu_grid_preview: 1]

  embed_templates "page_html/*"
end
