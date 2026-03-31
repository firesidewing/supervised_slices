defmodule SupervisedSlices.Cart do
  use Ash.Domain,
    otp_app: :supervised_slices,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource SupervisedSlices.Cart.Cart
    resource SupervisedSlices.Cart.CartItem
  end
end
