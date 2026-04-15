defmodule SupervisedSlices.Repo.Migrations.AllowNullCustomerEmail do
  @moduledoc """
  Removes the NOT NULL constraint from orders.customer_email to support
  phone orders where email is optional.
  """

  use Ecto.Migration

  def up do
    alter table(:orders) do
      modify :customer_email, :text, null: true
    end
  end

  def down do
    alter table(:orders) do
      modify :customer_email, :text, null: false
    end
  end
end
