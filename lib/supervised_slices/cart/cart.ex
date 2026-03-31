defmodule SupervisedSlices.Cart.Cart do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Cart,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]


  postgres do
    table "carts"
    repo SupervisedSlices.Repo

    custom_indexes do
      index [:status]
      index [:session_id], where: "status = 'active'"
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:session_id]

      change fn changeset, context ->
        case context.actor do
          %{id: user_id} -> Ash.Changeset.force_change_attribute(changeset, :user_id, user_id)
          _ -> changeset
        end
      end
    end

    update :checkout do
      accept []
      change set_attribute(:status, :checked_out)
    end

    update :abandon do
      accept []
      change set_attribute(:status, :abandoned)
    end

    update :claim do
      accept [:user_id]
    end

    read :active_for_session do
      argument :session_id, :string, allow_nil?: false
      get? true
      filter expr(session_id == ^arg(:session_id) and status == :active)
    end

    read :active_for_user do
      argument :user_id, :uuid, allow_nil?: false
      get? true
      filter expr(user_id == ^arg(:user_id) and status == :active)
    end

    read :active_for_org do
      filter expr(status == :active)
      prepare build(load: [cart_items: [:menu_item]])
    end
  end

  policies do
    policy action(:create) do
      authorize_if always()
    end

    policy action(:active_for_org) do
      authorize_if SupervisedSlices.Orgs.Checks.IsOrgAdmin
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
      authorize_if expr(session_id == ^actor(:session_id))
      authorize_if SupervisedSlices.Orgs.Checks.IsOrgAdmin
    end

    policy action_type(:update) do
      authorize_if relates_to_actor_via(:user)
      authorize_if expr(session_id == ^actor(:session_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :session_id, :string do
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:active, :checked_out, :abandoned]
      default :active
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
      public? true
    end

    has_many :cart_items, SupervisedSlices.Cart.CartItem
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end
end
