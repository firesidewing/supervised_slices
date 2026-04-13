defmodule SupervisedSlices.Orgs.Checks.IsOrgKitchenMember do
  @moduledoc """
  Reusable policy check that passes when the actor is an admin or staff member
  of the resource's organization. The resource must use attribute-based
  multitenancy with `organization_id` as the tenant attribute.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor is an org kitchen member (admin or staff)"

  @impl true
  def match?(nil, _context, _opts), do: false

  @impl true
  def match?(%SupervisedSlices.Accounts.GuestSession{} = _actor, _context, _opts), do: false

  def match?(actor, context, _opts) do
    org_id = context.subject.tenant

    if is_nil(org_id) or is_nil(actor.id) do
      false
    else
      require Ash.Query

      SupervisedSlices.Orgs.Membership
      |> Ash.Query.filter(
        user_id == ^actor.id and organization_id == ^org_id and role in [:admin, :staff]
      )
      |> Ash.read_one(authorize?: false)
      |> case do
        {:ok, %SupervisedSlices.Orgs.Membership{}} -> true
        _ -> false
      end
    end
  end
end
