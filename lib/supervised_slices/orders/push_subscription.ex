defmodule SupervisedSlices.Orders.PushSubscription do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Orders,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "push_subscriptions"
    repo SupervisedSlices.Repo

    custom_indexes do
      index [:user_id]
      index [:session_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      primary? true
      accept [:endpoint, :p256dh, :auth, :session_id, :user_id]

      upsert? true
      upsert_identity :endpoint
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :endpoint, :string do
      allow_nil? false
      public? true
    end

    attribute :p256dh, :string do
      allow_nil? false
      public? true
    end

    attribute :auth, :string do
      allow_nil? false
      public? true
    end

    attribute :session_id, :string do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, SupervisedSlices.Orgs.Organization do
      allow_nil? false
    end

    belongs_to :user, SupervisedSlices.Accounts.User do
      public? true
    end
  end

  identities do
    identity :endpoint, [:endpoint]
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end
end
