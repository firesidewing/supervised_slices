defmodule SupervisedSlices.Repo.Migrations.AddOperatingScheduleToOrganizations do
  @moduledoc """
  Adds the operating_schedule JSONB column to organizations.
  Stores weekly open/close times for controlling when orders can be placed.
  """

  use Ecto.Migration

  def up do
    alter table(:organizations) do
      add :operating_schedule, :map
    end
  end

  def down do
    alter table(:organizations) do
      remove :operating_schedule
    end
  end
end
