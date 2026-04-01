defmodule SupervisedSlices.Menu do
  use Ash.Domain,
    otp_app: :supervised_slices,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource SupervisedSlices.Menu.Category
    resource SupervisedSlices.Menu.MenuItem
    resource SupervisedSlices.Menu.SizeGroup
    resource SupervisedSlices.Menu.MenuItemSize
    resource SupervisedSlices.Menu.MenuItemModifierGroup
    resource SupervisedSlices.Menu.MenuItemModifier
    resource SupervisedSlices.Menu.MenuItemModifierGroupLink
  end
end
