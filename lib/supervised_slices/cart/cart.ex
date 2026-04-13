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

  code_interface do
    define :create, action: :create
    define :checkout, action: :checkout
    define :abandon, action: :abandon
    define :claim, action: :claim
    define :get, action: :read, get_by: :id
    define :active_for_session, action: :active_for_session, args: [:session_id]
    define :active_for_user, action: :active_for_user, args: [:user_id]
    define :active_for_org, action: :active_for_org
    define :update_delivery_type, action: :update_delivery_type
    define :update_delivery_address, action: :update_delivery_address
  end

  actions do
    defaults [:read]

    create :create do
      accept []

      change fn changeset, context ->
        changeset
        |> maybe_set_user(context)
        |> set_session_from_tenant(context)
      end
    end

    defp maybe_set_user(changeset, %{actor: %SupervisedSlices.Accounts.User{id: user_id}}) do
      Ash.Changeset.force_change_attribute(changeset, :user_id, user_id)
    end

    defp maybe_set_user(changeset, _), do: changeset

    defp set_session_from_tenant(changeset, %{
           actor: %SupervisedSlices.Accounts.GuestSession{id: session_id}
         })
         when not is_nil(session_id) do
      Ash.Changeset.force_change_attribute(changeset, :session_id, session_id)
    end

    defp set_session_from_tenant(changeset, _), do: changeset

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

    update :update_delivery_type do
      accept [:delivery_type]
    end

    update :update_delivery_address do
      argument :address, :map, allow_nil?: false
      change set_attribute(:delivery_address, arg(:address))
    end
  end

  policies do
    policy action(:create) do
      authorize_if always()
    end

    policy action(:active_for_org) do
      authorize_if SupervisedSlices.Orgs.Checks.IsOrgKitchenMember
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
      authorize_if expr(session_id == ^actor(:id))
      authorize_if SupervisedSlices.Orgs.Checks.IsOrgKitchenMember
    end

    policy action_type(:update) do
      authorize_if relates_to_actor_via(:user)
      authorize_if expr(session_id == ^actor(:id))
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
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

    attribute :delivery_type, :atom do
      constraints one_of: [:pickup, :delivery]
      default :pickup
      allow_nil? false
      public? true
    end

    attribute :delivery_address, SupervisedSlices.Orgs.Address do
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
end
