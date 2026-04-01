defmodule SupervisedSlices.Menu.MenuItemModifierGroup do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Menu,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "menu_item_modifier_groups"
    repo SupervisedSlices.Repo
  end

  code_interface do
    define :get, action: :read, get_by: :id
    define :create, action: :create
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :required, :min_selections, :max_selections, :sort_order, :menu_item_id]
    end

    update :update do
      accept [:name, :required, :min_selections, :max_selections, :sort_order]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if SupervisedSlices.Orgs.Checks.IsOrgAdmin
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :required, :boolean do
      default false
      allow_nil? false
      public? true
    end

    attribute :min_selections, :integer do
      default 0
      public? true
    end

    attribute :max_selections, :integer do
      public? true
    end

    attribute :sort_order, :integer do
      default 0
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
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

    has_many :modifiers, SupervisedSlices.Menu.MenuItemModifier do
      destination_attribute :modifier_group_id
    end
  end
end
