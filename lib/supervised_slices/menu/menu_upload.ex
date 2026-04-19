defmodule SupervisedSlices.Menu.MenuUpload do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Menu,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  postgres do
    table "menu_uploads"
    repo SupervisedSlices.Repo
  end

  oban do
    triggers do
      trigger :process do
        action :process
        queue :menu_uploads
        where expr(status == :pending)
        worker_module_name SupervisedSlices.Menu.MenuUpload.AshOban.Worker.Process
        scheduler_module_name SupervisedSlices.Menu.MenuUpload.AshOban.Scheduler.Process
      end
    end
  end

  code_interface do
    define :create, action: :create
    define :process, action: :process
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:file_url, :organization_id]
      primary? true

      validate {SupervisedSlices.Menu.MenuUpload.Validations.PurchaseRequired, []}
      validate {SupervisedSlices.Menu.MenuUpload.Validations.SingleUse, []}

      change set_attribute(:status, :pending)
    end

    update :process do
      accept []
      primary? true
      require_atomic? false

      change set_attribute(:status, :processing)

      change fn changeset, _ ->
        Ash.Changeset.after_action(changeset, fn _changeset, upload ->
          case SupervisedSlices.Menu.Parser.parse(upload.file_url) do
            {:ok, %SupervisedSlices.Menu.Parser.ParsedMenu{} = parsed} ->
              try do
                Enum.each(categories, fn cat_data ->
                  tenant = upload.organization_id

                  cat =
                    SupervisedSlices.Menu.Category
                    |> Ash.Changeset.for_create(:create, %{
                      name: cat_data["name"] || "Uncategorized",
                      sort_order: cat_data["sort_order"] || 0
                    })
                    |> Ash.Changeset.set_tenant(tenant)
                    |> Ash.create!(authorize?: false)

                  Enum.each(cat_data.items, fn item_data ->
                    price =
                      if item_data.price,
                        do: Money.new!(:CAD, item_data.price),
                        else: nil

                    item =
                      SupervisedSlices.Menu.MenuItem
                      |> Ash.Changeset.for_create(:create, %{
                        name: item_data.name || "Unnamed Item",
                        description: item_data.description,
                        price: price,
                        sort_order: item_data["sort_order"] || 0,
                        category_id: cat.id
                      })
                      |> Ash.Changeset.set_tenant(tenant)
                      |> Ash.create!(authorize?: false)

                    Enum.each(item_data.sizes, fn size_data ->
                      size_price = Money.new!(:CAD, size_data.price || 0)

                      SupervisedSlices.Menu.MenuItemSize
                      |> Ash.Changeset.for_create(:create, %{
                        name: size_data.name || "Regular",
                        price: size_price,
                        sort_order: size_data["sort_order"] || 0,
                        menu_item_id: item.id
                      })
                      |> Ash.Changeset.set_tenant(tenant)
                      |> Ash.create!(authorize?: false)
                    end)

                    Enum.each(item_data.modifier_group_names, fn name ->
                      if group = Map.get(group_map, name) do
                        SupervisedSlices.Menu.MenuItemModifierGroupLink
                        |> Ash.Changeset.for_create(:create, %{
                          name: group_data["name"] || "Options",
                          required: group_data["required"] || false,
                          min_selections: group_data["min_selections"] || 0,
                          max_selections: group_data["max_selections"],
                          sort_order: group_data["sort_order"] || 0
                        })
                        |> Ash.Changeset.set_tenant(tenant)
                        |> Ash.create!(authorize?: false)

                      SupervisedSlices.Menu.MenuItemModifierGroupLink
                      |> Ash.Changeset.for_create(:create, %{
                        menu_item_id: item.id,
                        modifier_group_id: group.id
                      })
                      |> Ash.Changeset.set_tenant(tenant)
                      |> Ash.create!(authorize?: false)

                      Enum.each(group_data["modifiers"] || [], fn modifier_data ->
                        price_delta =
                          if is_integer(modifier_data["price_delta"]) &&
                               modifier_data["price_delta"] != 0,
                             do: Money.new!(:CAD, modifier_data["price_delta"]),
                             else: nil

                        SupervisedSlices.Menu.MenuItemModifier
                        |> Ash.Changeset.for_create(:create, %{
                          name: modifier_data["name"] || "Option",
                          price_delta: price_delta,
                          sort_order: modifier_data["sort_order"] || 0,
                          modifier_group_id: group.id
                        })
                        |> Ash.Changeset.set_tenant(tenant)
                        |> Ash.create!(authorize?: false)
                      end
                    end)
                  end)
                end)

                upload
                |> Ash.Changeset.for_update(:complete, %{})
                |> Ash.update!(authorize?: false)
              rescue
                e ->
                  upload
                  |> Ash.Changeset.for_update(:fail, %{error_message: Exception.message(e)})
                  |> Ash.update!(authorize?: false)
              end

            {:error, reason} ->
              upload
              |> Ash.Changeset.for_update(:fail, %{error_message: to_string(reason)})
              |> Ash.update!(authorize?: false)
          end

          {:ok, upload}
        end)
      end
    end

    update :complete do
      accept []
      change set_attribute(:status, :completed)
    end

    update :fail do
      accept [:error_message]
      change set_attribute(:status, :failed)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      constraints one_of: [:pending, :processing, :completed, :failed]
      default :pending
      allow_nil? false
      public? true
    end

    attribute :file_url, :string do
      allow_nil? false
      public? true
    end

    attribute :error_message, :string do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, SupervisedSlices.Orgs.Organization do
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end
end

defmodule SupervisedSlices.Menu.MenuUpload.Validations.PurchaseRequired do
  use Ash.Resource.Validation

  def validate(changeset, _opts, _context) do
    org_id = Ash.Changeset.get_attribute(changeset, :organization_id)

    if org_id do
      org =
        SupervisedSlices.Orgs.Organization
        |> Ash.get!(org_id, authorize?: false)

      if org.menu_upload_purchased do
        :ok
      else
        {:error,
         field: :organization_id,
         message: "Menu upload has not been purchased for this organization."}
      end
    else
      :ok
    end
  end
end

defmodule SupervisedSlices.Menu.MenuUpload.Validations.SingleUse do
  use Ash.Resource.Validation

  def validate(changeset, _opts, _context) do
    org_id = Ash.Changeset.get_attribute(changeset, :organization_id)

    if org_id do
      require Ash.Query

      exists? =
        SupervisedSlices.Menu.MenuUpload
        |> Ash.Query.filter(organization_id == ^org_id and status == :completed)
        |> Ash.read_one!(authorize?: false)
        |> case do
          nil -> false
          _ -> true
        end

      if exists? do
        {:error,
         field: :organization_id,
         message: "A menu has already been uploaded for this organization."}
      else
        :ok
      end
    else
      :ok
    end
  end
end
