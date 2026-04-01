defmodule SupervisedSlices.Menu.MenuItem do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Menu,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "menu_items"
    repo SupervisedSlices.Repo

    custom_indexes do
      index [:available]
    end
  end

  code_interface do
    define :get, action: :read, get_by: :id
    define :create, action: :create
    define :update, action: :update
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :description, :price, :sort_order, :image_url, :category_id, :size_group_id]
    end

    update :update do
      accept [
        :name,
        :description,
        :price,
        :available,
        :sort_order,
        :image_url,
        :category_id,
        :size_group_id
      ]
    end

    read :available do
      filter expr(available == true)
      prepare build(sort: [sort_order: :asc], load: [:modifier_groups])
    end

    read :for_category do
      argument :category_id, :uuid, allow_nil?: false
      filter expr(category_id == ^arg(:category_id) and available == true)
      prepare build(sort: [sort_order: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if SupervisedSlices.Orgs.Checks.IsOrgAdmin
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :price, AshMoney.Types.Money do
      public? true
    end

    attribute :available, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :sort_order, :integer do
      default 0
      allow_nil? false
      public? true
    end

    attribute :image_url, :string do
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

    belongs_to :category, SupervisedSlices.Menu.Category do
      allow_nil? false
      public? true
    end

    belongs_to :size_group, SupervisedSlices.Menu.SizeGroup do
      public? true
    end

    many_to_many :modifier_groups, SupervisedSlices.Menu.MenuItemModifierGroup do
      through SupervisedSlices.Menu.MenuItemModifierGroupLink
      source_attribute_on_join_resource :menu_item_id
      destination_attribute_on_join_resource :modifier_group_id
      public? true
    end
  end
end
