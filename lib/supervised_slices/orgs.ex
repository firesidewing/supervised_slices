defmodule SupervisedSlices.Orgs do
  use Ash.Domain,
    otp_app: :supervised_slices,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource SupervisedSlices.Orgs.Organization
    resource SupervisedSlices.Orgs.Membership
  end
end
