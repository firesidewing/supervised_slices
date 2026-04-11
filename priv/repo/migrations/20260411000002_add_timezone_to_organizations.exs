defmodule SupervisedSlices.Repo.Migrations.AddTimezoneToOrganizations do
  use Ecto.Migration

  def up do
    alter table(:organizations) do
      add :timezone, :string, default: "Etc/UTC"
    end
  end

  def down do
    alter table(:organizations) do
      remove :timezone
    end
  end
end
