defmodule SupervisedSlices.Menu.MenuItemImage do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Menu,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "menu_item_images"
    repo SupervisedSlices.Repo
  end

  code_interface do
    define :create, action: :create
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:url, :position, :menu_item_id]
    end
  end

  changes do
    change SupervisedSlices.Menu.Changes.InvalidateMenuCache, on: [:create, :update, :destroy]
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

    attribute :url, :string do
      allow_nil? false
      public? true
    end

    attribute :position, :integer do
      default 0
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :menu_item, SupervisedSlices.Menu.MenuItem do
      allow_nil? false
      public? true
    end

    belongs_to :organization, SupervisedSlices.Orgs.Organization do
      allow_nil? false
      public? true
    end
  end
end
