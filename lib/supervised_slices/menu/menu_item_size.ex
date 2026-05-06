defmodule SupervisedSlices.Menu.MenuItemSize do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Menu,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "menu_item_sizes"
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
      accept [:name, :price, :sort_order, :menu_item_id]
    end

    update :update do
      accept [:name, :price, :sort_order, :available]
    end
  end

  changes do
    change SupervisedSlices.Menu.Changes.InvalidateMenuCache, on: [:create, :update, :destroy]
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

    attribute :price, AshMoney.Types.Money do
      allow_nil? false
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

    belongs_to :menu_item, SupervisedSlices.Menu.MenuItem do
      allow_nil? false
      public? true
    end
  end
end
