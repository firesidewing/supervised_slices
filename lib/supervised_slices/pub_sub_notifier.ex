defmodule SupervisedSlices.PubSubNotifier do
  @moduledoc """
  Typed broadcast helpers for real-time events. Called from resource
  `after_action` hooks and LiveView cart event handlers.

  Topic conventions:
    "orders:{org_id}"              — new order placed / order updated (admin kitchen view)
    "orders:{org_id}:{order_id}"   — order status changed (customer order tracking)
    "carts:{org_id}"               — cart snapshot updated (admin sees live carts)
  """

  @pubsub SupervisedSlices.PubSub

  # ---------------------------------------------------------------------------
  # Broadcasts
  # ---------------------------------------------------------------------------

  @doc "Broadcast a newly placed order to the org's admin kitchen view."
  def broadcast_new_order(%{organization_id: org_id} = order) do
    Phoenix.PubSub.broadcast(@pubsub, "orders:#{org_id}", {:new_order, order})
  end

  @doc """
  Broadcast an order status change to both the org-level topic (admin dashboard)
  and the order-level topic (customer tracking their specific order).
  """
  def broadcast_order_status(%{organization_id: org_id, id: order_id} = order) do
    Phoenix.PubSub.broadcast(@pubsub, "orders:#{org_id}:#{order_id}", {:order_status, order})
    Phoenix.PubSub.broadcast(@pubsub, "orders:#{org_id}", {:order_updated, order})
  end

  @doc "Broadcast a cart snapshot after an item is added, updated, or removed."
  def broadcast_cart_update(%{organization_id: org_id} = cart) do
    Phoenix.PubSub.broadcast(@pubsub, "carts:#{org_id}", {:cart_updated, cart})
  end

  @doc "Broadcast a kitchen update message for a specific order (customer tracking)."
  def broadcast_order_update(%{organization_id: org_id, order_id: order_id} = update) do
    Phoenix.PubSub.broadcast(@pubsub, "orders:#{org_id}:#{order_id}", {:order_update, update})
  end

  # ---------------------------------------------------------------------------
  # Subscribe helpers (for use in LiveView mount/handle_info)
  # ---------------------------------------------------------------------------

  @doc "Subscribe to all order events for an org (admin kitchen display)."
  def subscribe_to_org_orders(org_id) do
    Phoenix.PubSub.subscribe(@pubsub, "orders:#{org_id}")
  end

  @doc "Subscribe to status changes for a specific order (customer order tracking)."
  def subscribe_to_order(org_id, order_id) do
    Phoenix.PubSub.subscribe(@pubsub, "orders:#{org_id}:#{order_id}")
  end

  @doc "Subscribe to cart updates for an org (admin sees live cart contents)."
  def subscribe_to_org_carts(org_id) do
    Phoenix.PubSub.subscribe(@pubsub, "carts:#{org_id}")
  end

end
