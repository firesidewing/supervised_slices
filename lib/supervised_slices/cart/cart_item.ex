defmodule SupervisedSlices.Cart.CartItem do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Cart,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "cart_items"
    repo SupervisedSlices.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :add_to_cart do
      accept [:cart_id, :menu_item_id, :quantity, :selected_modifier_ids]
    end

    update :update_quantity do
      accept [:quantity, :selected_modifier_ids]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if relates_to_actor_via([:cart, :user])
      authorize_if expr(cart.session_id == ^actor(:session_id))
      authorize_if SupervisedSlices.Orgs.Checks.IsOrgAdmin
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if relates_to_actor_via([:cart, :user])
      authorize_if expr(cart.session_id == ^actor(:session_id))
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

    attribute :selected_modifier_ids, {:array, :uuid} do
      default []
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

    belongs_to :cart, SupervisedSlices.Cart.Cart do
      allow_nil? false
      public? true
    end

    belongs_to :menu_item, SupervisedSlices.Menu.MenuItem do
      allow_nil? false
      public? true
    end
  end
end
