defmodule SupervisedSlices.Orders.OrderUpdate do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "order_updates"
    repo SupervisedSlices.Repo
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  code_interface do
    define :create
    define :for_order, args: [:order_id]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:status, :message, :order_id]
    end

    read :for_order do
      argument :order_id, :uuid, allow_nil?: false
      filter expr(order_id == ^arg(:order_id))
      prepare build(sort: [inserted_at: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:create) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      constraints one_of: [:pending, :confirmed, :preparing, :ready, :completed, :cancelled]
      allow_nil? true
      public? true
    end

    attribute :message, :string do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :organization, SupervisedSlices.Orgs.Organization do
      allow_nil? false
      public? true
    end

    belongs_to :order, SupervisedSlices.Orders.Order do
      allow_nil? false
      public? true
    end
  end
end
