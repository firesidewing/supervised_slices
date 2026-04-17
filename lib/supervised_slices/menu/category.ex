defmodule SupervisedSlices.Menu.Category do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Menu,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "menu_categories"
    repo SupervisedSlices.Repo
  end

  code_interface do
    define :get, action: :read, get_by: :id
    define :create, action: :create
    define :update, action: :update
    define :active, action: :active
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :sort_order]
    end

    update :update do
      accept [:name, :sort_order, :active]
    end

    read :active do
      filter expr(active == true)
      prepare build(sort: [sort_order: :asc])
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

    attribute :sort_order, :integer do
      default 0
      allow_nil? false
      public? true
    end

    attribute :active, :boolean do
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

    has_many :menu_items, SupervisedSlices.Menu.MenuItem do
      sort sort_order: :asc
    end
  end
end
