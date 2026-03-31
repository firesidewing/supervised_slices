defmodule SupervisedSlices.Orgs.Membership do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Orgs,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]


  postgres do
    table "memberships"
    repo SupervisedSlices.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:role, :organization_id, :user_id]
    end

    update :update_role do
      accept [:role]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)

      authorize_if expr(
        exists(
          organization.memberships,
          user_id == ^actor(:id) and role == :admin
        )
      )
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:superadmin, true)

      authorize_if expr(
        exists(
          organization.memberships,
          user_id == ^actor(:id) and role == :admin
        )
      )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      constraints one_of: [:admin, :customer]
      default :customer
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

    belongs_to :user, SupervisedSlices.Accounts.User do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_user_org, [:user_id, :organization_id]
  end
end
