defmodule SupervisedSlices.Accounts do
  use Ash.Domain, otp_app: :supervised_slices, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource SupervisedSlices.Accounts.Token
    resource SupervisedSlices.Accounts.User
  end
end
