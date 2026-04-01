defmodule SupervisedSlices.Orders.Order do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "orders"
    repo SupervisedSlices.Repo

    custom_indexes do
      index [:status]
      index [:user_id]
    end
  end

  code_interface do
    define :get, action: :read, get_by: :id
    define :place_order, action: :place_order
    define :update_status, action: :update_status
    define :active, action: :active
    define :all, action: :all
  end

  actions do
    defaults [:read]

    create :place_order do
      accept [:customer_name, :customer_phone, :customer_email, :notes, :total_price]

      change fn changeset, context ->
        changeset =
          case context.actor do
            %SupervisedSlices.Accounts.User{id: user_id} ->
              Ash.Changeset.force_change_attribute(changeset, :user_id, user_id)

            _ ->
              changeset
          end

        case context.actor do
          %SupervisedSlices.Accounts.GuestSession{id: id} ->
            Ash.Changeset.force_change_attribute(changeset, :session_id, id)

          _ ->
            changeset
        end
      end
    end

    update :update_status do
      accept [:status]

      after_action(fn _changeset, order, _context ->
        SupervisedSlices.PubSubNotifier.broadcast_order_status(order)
        {:ok, order}
      end)
    end

    read :all do
      prepare build(sort: [inserted_at: :desc], load: [:order_items])
    end

    read :active do
      filter expr(status not_in([:completed, :cancelled]))
      prepare build(sort: [inserted_at: :asc], load: [:order_items])
    end

    read :for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
      prepare build(sort: [inserted_at: :desc])
    end
  end

  policies do
    policy action(:place_order) do
      authorize_if always()
    end

    policy action(:update_status) do
      authorize_if SupervisedSlices.Orgs.Checks.IsOrgAdmin
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
      authorize_if expr(session_id == ^actor(:id))
      authorize_if SupervisedSlices.Orgs.Checks.IsOrgAdmin
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      constraints one_of: [:pending, :confirmed, :preparing, :ready, :completed, :cancelled]
      default :pending
      allow_nil? false
      public? true
    end

    attribute :total_price, AshMoney.Types.Money do
      allow_nil? false
      public? true
    end

    attribute :customer_name, :string do
      allow_nil? false
      public? true
    end

    attribute :customer_phone, :string do
      public? true
    end

    attribute :customer_email, :string do
      public? true
    end

    attribute :notes, :string do
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
      public? true
    end

    belongs_to :user, SupervisedSlices.Accounts.User do
      public? true
    end

    has_many :order_items, SupervisedSlices.Orders.OrderItem
  end
end
