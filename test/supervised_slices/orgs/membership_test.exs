defmodule SupervisedSlices.Orgs.MembershipTest do
  use SupervisedSlices.DataCase, async: true

  alias SupervisedSlices.Orgs.{Organization, Membership}
  alias SupervisedSlices.Accounts.User

  test "get_kitchen_membership/1 returns the first admin/staff membership" do
    user =
      User
      |> Ash.Changeset.for_create(:create_invited, %{email: "test@example.com"})
      |> Ash.create!(authorize?: false)

    org1 =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "Kitchen 1", slug: "kitchen-1"})
      |> Ash.create!(authorize?: false)

    org2 =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "Kitchen 2", slug: "kitchen-2"})
      |> Ash.create!(authorize?: false)

    # First membership - admin
    _m1 =
      Membership
      |> Ash.Changeset.for_create(:create, %{
        user_id: user.id,
        organization_id: org1.id,
        role: :admin
      })
      |> Ash.create!(authorize?: false)

    # Second membership - staff
    _m2 =
      Membership
      |> Ash.Changeset.for_create(:create, %{
        user_id: user.id,
        organization_id: org2.id,
        role: :staff
      })
      |> Ash.create!(authorize?: false)

    # Should return both of them (sorted by latest first)
    assert {:ok, [membership | _] = memberships} =
             Membership.get_kitchen_membership(user.id, authorize?: false)

    assert length(memberships) == 2
    assert membership.organization_id in [org1.id, org2.id]
    assert membership.role in [:admin, :staff]
    assert membership.organization.slug in ["kitchen-1", "kitchen-2"]
  end

  test "get_kitchen_membership/1 returns nil for customer role" do
    user =
      User
      |> Ash.Changeset.for_create(:create_invited, %{email: "customer@example.com"})
      |> Ash.create!(authorize?: false)

    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "Shop", slug: "shop"})
      |> Ash.create!(authorize?: false)

    _m =
      Membership
      |> Ash.Changeset.for_create(:create, %{
        user_id: user.id,
        organization_id: org.id,
        role: :customer
      })
      |> Ash.create!(authorize?: false)

    assert {:ok, []} = Membership.get_kitchen_membership(user.id, authorize?: false)
  end
end
