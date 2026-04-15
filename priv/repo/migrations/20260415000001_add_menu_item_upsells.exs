defmodule SupervisedSlices.Repo.Migrations.AddMenuItemUpsells do
  @moduledoc """
  Creates the menu_item_upsells join table for the upselling feature.
  Admins can link menu items to other items that should be suggested
  when the source item is in a customer's cart.
  """

  use Ecto.Migration

  def up do
    create table(:menu_item_upsells, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :organization_id,
          references(:organizations,
            column: :id,
            name: "menu_item_upsells_organization_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false

      add :source_menu_item_id,
          references(:menu_items,
            column: :id,
            name: "menu_item_upsells_source_menu_item_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false

      add :upsell_menu_item_id,
          references(:menu_items,
            column: :id,
            name: "menu_item_upsells_upsell_menu_item_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    create index(:menu_item_upsells, [:organization_id])

    create unique_index(:menu_item_upsells, [:source_menu_item_id, :upsell_menu_item_id],
             name: "menu_item_upsells_source_upsell_unique_index"
           )
  end

  def down do
    drop constraint(:menu_item_upsells, "menu_item_upsells_upsell_menu_item_id_fkey")
    drop constraint(:menu_item_upsells, "menu_item_upsells_source_menu_item_id_fkey")
    drop constraint(:menu_item_upsells, "menu_item_upsells_organization_id_fkey")
    drop table(:menu_item_upsells)
  end
end
