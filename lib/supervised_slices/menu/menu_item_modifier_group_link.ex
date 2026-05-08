defmodule SupervisedSlices.Menu.MenuItemModifierGroupLink do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Menu,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "menu_items_modifier_groups"
    repo SupervisedSlices.Repo

    references do
      reference :modifier_group, on_delete: :delete
    end
  end

  code_interface do
    define :assign, action: :create
    define :get, action: :read, get_by: :id
    define :unassign, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:menu_item_id, :modifier_group_id]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :destroy]) do
      authorize_if SupervisedSlices.Orgs.Checks.IsOrgAdmin
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_primary_key :id

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :organization, SupervisedSlices.Orgs.Organization do
      allow_nil? false
      public? true
    end

    belongs_to :menu_item, SupervisedSlices.Menu.MenuItem do
      allow_nil? false
      public? true
    end

    belongs_to :modifier_group, SupervisedSlices.Menu.MenuItemModifierGroup do
      allow_nil? false
      public? true
    end
  end
end
