defmodule SupervisedSlices.Orgs.Checks.IsOrgAdmin do
  @moduledoc """
  Reusable policy check that passes when the actor is an admin member of the
  resource's organization. The resource must have a `belongs_to :organization`
  relationship that has a `has_many :memberships` relationship on Organization.
  """
  use Ash.Policy.FilterCheck

  @impl true
  def describe(_opts), do: "actor is an org admin"

  @impl true
  def filter(_actor, _authorizer, _opts) do
    {:ok,
     expr(
       exists(
         organization.memberships,
         user_id == ^actor(:id) and role == :admin
       )
     )}
  end
end
