defmodule SupervisedSlices.Menu.MenuItemUpsell do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Menu,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "menu_item_upsells"
    repo SupervisedSlices.Repo
  end

  code_interface do
    define :assign, action: :create
    define :get, action: :read, get_by: :id
    define :unassign, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:source_menu_item_id, :upsell_menu_item_id]
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

    belongs_to :source_item, SupervisedSlices.Menu.MenuItem do
      attribute_writable? true
      source_attribute :source_menu_item_id
      allow_nil? false
      public? true
    end

    belongs_to :upsell_item, SupervisedSlices.Menu.MenuItem do
      attribute_writable? true
      source_attribute :upsell_menu_item_id
      allow_nil? false
      public? true
    end
  end
end
