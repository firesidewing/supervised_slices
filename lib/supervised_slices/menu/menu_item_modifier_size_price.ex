defmodule SupervisedSlices.Menu.MenuItemModifierSizePrice do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Menu,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "menu_item_modifier_size_prices"
    repo SupervisedSlices.Repo
  end

  code_interface do
    define :upsert, action: :upsert
    define :get, action: :read, get_by: :id
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      upsert? true
      upsert_identity :modifier_and_size
      accept [:modifier_id, :size_id, :price_delta]
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

    attribute :price_delta, AshMoney.Types.Money do
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

    belongs_to :modifier, SupervisedSlices.Menu.MenuItemModifier do
      allow_nil? false
      public? true
    end

    belongs_to :size, SupervisedSlices.Menu.MenuItemSize do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :modifier_and_size, [:modifier_id, :size_id]
  end
end
