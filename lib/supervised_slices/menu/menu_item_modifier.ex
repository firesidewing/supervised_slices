defmodule SupervisedSlices.Menu.MenuItemModifier do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Menu,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "menu_item_modifiers"
    repo SupervisedSlices.Repo

    references do
      reference :modifier_group, on_delete: :delete
    end
  end

  code_interface do
    define :get, action: :read, get_by: :id
    define :create, action: :create
    define :update, action: :update
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :price_delta, :sort_order, :modifier_group_id]
    end

    update :update do
      accept [:name, :price_delta, :sort_order, :available]
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

    attribute :price_delta, AshMoney.Types.Money do
      public? true
    end

    attribute :sort_order, :integer do
      default 0
      allow_nil? false
      public? true
    end

    attribute :available, :boolean do
      default true
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

    belongs_to :modifier_group, SupervisedSlices.Menu.MenuItemModifierGroup do
      allow_nil? false
      public? true
    end

    has_many :size_prices, SupervisedSlices.Menu.MenuItemModifierSizePrice do
      destination_attribute :modifier_id
    end
  end
end
