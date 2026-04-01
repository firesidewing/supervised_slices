defmodule SupervisedSlices.Orders.OrderItem do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "order_items"
    repo SupervisedSlices.Repo
  end

  code_interface do
    define :create, action: :create
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :order_id,
        :menu_item_id,
        :quantity,
        :item_name,
        :price_at_time,
        :modifiers_snapshot,
        :size_snapshot
      ]
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via([:order, :user])
      authorize_if expr(order.session_id == ^actor(:id))
      authorize_if SupervisedSlices.Orgs.Checks.IsOrgAdmin
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_primary_key :id

    attribute :quantity, :integer do
      allow_nil? false
      constraints min: 1
      public? true
    end

    attribute :item_name, :string do
      allow_nil? false
      public? true
    end

    attribute :price_at_time, AshMoney.Types.Money do
      allow_nil? false
      public? true
    end

    attribute :modifiers_snapshot, {:array, :map} do
      default []
      public? true
    end

    attribute :size_snapshot, :map do
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

    belongs_to :order, SupervisedSlices.Orders.Order do
      allow_nil? false
      public? true
    end

    belongs_to :menu_item, SupervisedSlices.Menu.MenuItem do
      public? true
    end
  end

  calculations do
    calculate :line_total, AshMoney.Types.Money, expr(price_at_time * quantity)
  end
end
