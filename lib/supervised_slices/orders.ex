defmodule SupervisedSlices.Orders do
  use Ash.Domain,
    otp_app: :supervised_slices,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource SupervisedSlices.Orders.Order
    resource SupervisedSlices.Orders.OrderItem
    resource SupervisedSlices.Orders.OrderUpdate
    resource SupervisedSlices.Orders.PushSubscription
  end
end
