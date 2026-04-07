defmodule SupervisedSlices.Orgs.Organization do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Orgs,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "organizations"
    repo SupervisedSlices.Repo
  end

  code_interface do
    define :update_settings, action: :update_settings
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :slug]
    end

    update :update do
      accept [:name, :active]
    end

    update :update_settings do
      accept [:tax_rate]
    end

    read :by_slug do
      argument :slug, :string, allow_nil?: false
      get? true
      filter expr(slug == ^arg(:slug))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:update_settings) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:superadmin, true)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
    end

    attribute :active, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :tax_rate, :decimal do
      default Decimal.new("0")
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :memberships, SupervisedSlices.Orgs.Membership
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
