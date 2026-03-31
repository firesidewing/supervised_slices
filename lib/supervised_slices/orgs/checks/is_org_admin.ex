defmodule SupervisedSlices.Orgs.Checks.IsOrgAdmin do
  @moduledoc """
  Reusable policy check that passes when the actor is an admin member of the
  resource's organization. The resource must have a `belongs_to :organization`
  relationship that has a `has_many :memberships` relationship on Organization.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor is an org admin"

  @impl true
  def match?(actor, context, _opts) do
    org_id =
      case context do
        %{changeset: cs} -> cs.tenant
        %{resource: record} -> record.organization_id
        _ -> nil
      end

    actor.org_role == :admin and actor.org_id == org_id
  end
end
