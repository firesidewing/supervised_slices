defmodule SupervisedSlices.Repo.Migrations.AddStripeBillingToOrganizations do
  @moduledoc """
  Adds Stripe billing fields to organizations so each org can maintain a
  Stripe customer and subscription without any manual developer intervention.
  """

  use Ecto.Migration

  def up do
    alter table(:organizations) do
      add :stripe_customer_id, :text, null: true
      add :stripe_subscription_id, :text, null: true
      add :subscription_status, :text, null: false, default: "none"
    end
  end

  def down do
    alter table(:organizations) do
      remove :stripe_customer_id
      remove :stripe_subscription_id
      remove :subscription_status
    end
  end
end
