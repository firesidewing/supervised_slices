defmodule SupervisedSlices.Orders.Order do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  postgres do
    table "orders"
    repo SupervisedSlices.Repo

    custom_indexes do
      index [:status]
      index [:user_id]
    end
  end

  oban do
    triggers do
      trigger :place_order do
        action :notify_order
        worker_module_name SupervisedSlices.Orders.Order.AshOban.Worker.NotifyOrder
        scheduler_module_name SupervisedSlices.Orders.Order.AshOban.Scheduler.NotifyOrder
      end
    end
  end

  code_interface do
    define :get, action: :read, get_by: :id
    define :place_order, action: :place_order
    define :place_phone_order, action: :place_phone_order
    define :update_status, action: :update_status
    define :send_update, action: :send_update
    define :active, action: :active
    define :all, action: :all
    define :for_user, args: [:user_id]
    define :completed_orders, action: :completed
  end

  actions do
    defaults [:read]

    create :place_order do
      accept [
        :customer_name,
        :customer_phone,
        :customer_email,
        :notes,
        :total_price,
        :tax_amount,
        :delivery_type,
        :delivery_fee
      ]

      validate present(:customer_email)

      argument :delivery_address, :map

      change set_attribute(:delivery_address, arg(:delivery_address))

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

      change fn changeset, _context ->
        delivery_type = Ash.Changeset.get_attribute(changeset, :delivery_type)

        if delivery_type == :delivery do
          address = Ash.Changeset.get_argument(changeset, :delivery_address) || %{}

          blank = fn v -> is_nil(v) or String.trim(to_string(v)) == "" end

          street = address["street"] || address[:street]
          city = address["city"] || address[:city]
          zip = address["zip"] || address[:zip]

          cond do
            blank.(street) ->
              Ash.Changeset.add_error(changeset,
                field: :delivery_address,
                message: "street address is required for delivery orders"
              )

            blank.(city) ->
              Ash.Changeset.add_error(changeset,
                field: :delivery_address,
                message: "city is required for delivery orders"
              )

            blank.(zip) ->
              Ash.Changeset.add_error(changeset,
                field: :delivery_address,
                message: "postal code is required for delivery orders"
              )

            true ->
              changeset
          end
        else
          changeset
        end
      end
    end

    create :place_phone_order do
      accept [
        :customer_name,
        :customer_phone,
        :customer_email,
        :notes,
        :total_price,
        :tax_amount,
        :delivery_type,
        :delivery_fee
      ]

      change fn changeset, context ->
        case context.actor do
          %SupervisedSlices.Accounts.User{id: user_id} ->
            Ash.Changeset.force_change_attribute(changeset, :user_id, user_id)

          _ ->
            changeset
        end
      end
    end

    update :update_status do
      accept [:status]
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn _changeset, order ->
          SupervisedSlices.Orders.OrderUpdate
          |> Ash.Changeset.for_create(:create, %{order_id: order.id, status: order.status})
          |> Ash.create!(
            tenant: order.organization_id,
            authorize?: false
          )

          {:ok, order}
        end)
      end

      change fn changeset, _context ->
        Ash.Changeset.after_transaction(changeset, fn _changeset, result ->
          case result do
            {:ok, order} ->
              SupervisedSlices.PubSubNotifier.broadcast_order_status(order)
              {:ok, order}

            other ->
              other
          end
        end)
      end
    end

    update :send_update do
      argument :message, :string, allow_nil?: false
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn changeset, order ->
          message = Ash.Changeset.get_argument(changeset, :message)

          {:ok, update} =
            SupervisedSlices.Orders.OrderUpdate
            |> Ash.Changeset.for_create(:create, %{order_id: order.id, message: message})
            |> Ash.create(
              tenant: order.organization_id,
              authorize?: false
            )

          SupervisedSlices.PubSubNotifier.broadcast_order_update(update)
          {:ok, order}
        end)
      end
    end

    read :all do
      prepare build(sort: [inserted_at: :desc], load: [:order_items])
    end

    read :completed do
      filter expr(status in [:completed, :cancelled])
      prepare build(sort: [inserted_at: :desc], load: [:order_items])
    end

    read :active do
      filter expr(status not in [:completed, :cancelled])
      prepare build(sort: [inserted_at: :desc], load: [:order_items])
    end

    read :for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
      prepare build(sort: [inserted_at: :desc])
    end

    action :notify_order do
      argument :order_id, :uuid, allow_nil?: false

      run fn input, _context ->
        order = Ash.get!(SupervisedSlices.Orders.Order, input.arguments.order_id)
        SupervisedSlices.PubSubNotifier.broadcast_new_order(order)
        SupervisedSlices.Emails.send_order_confirmation(order)
        {:ok, order}
      end
    end
  end

  policies do
    policy action(:place_order) do
      authorize_if always()
    end

    policy action(:place_phone_order) do
      authorize_if SupervisedSlices.Orgs.Checks.IsOrgKitchenMember
    end

    policy action(:update_status) do
      authorize_if SupervisedSlices.Orgs.Checks.IsOrgKitchenMember
    end

    policy action(:send_update) do
      authorize_if SupervisedSlices.Orgs.Checks.IsOrgKitchenMember
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
      authorize_if expr(session_id == ^actor(:id))
      authorize_if SupervisedSlices.Orgs.Checks.IsOrgKitchenMember
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

    attribute :tax_amount, AshMoney.Types.Money do
      allow_nil? true
      public? true
    end

    attribute :customer_name, :string do
      allow_nil? false
      public? true
    end

    attribute :customer_phone, :string do
      allow_nil? true
      public? true
    end

    attribute :customer_email, :string do
      allow_nil? true
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    attribute :delivery_type, :atom do
      constraints one_of: [:pickup, :delivery]
      default :pickup
      allow_nil? false
      public? true
    end

    attribute :delivery_address, SupervisedSlices.Orgs.Address do
      public? true
    end

    attribute :delivery_fee, AshMoney.Types.Money do
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

    has_many :order_updates, SupervisedSlices.Orders.OrderUpdate do
      sort inserted_at: :asc
    end
  end
end
