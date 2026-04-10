defmodule SupervisedSlices.Accounts.UserTest do
  use SupervisedSlices.DataCase

  alias SupervisedSlices.Accounts.User
  alias SupervisedSlices.Orgs.Organization
  alias SupervisedSlices.Orgs.Membership

  require Ash.Query

  describe "register_with_password" do
    test "registers a user and creates an organization and membership" do
      email = "test@example.com"
      password = "password1234"
      org_name = "Test Org"

      assert {:ok, user} =
               User
               |> Ash.Changeset.for_create(:register_with_password, %{
                 email: email,
                 password: password,
                 password_confirmation: password,
                 organization_name: org_name
               })
               |> Ash.create(authorize?: false)

      assert user.email == Ash.CiString.new(email)

      # Verify organization
      org =
        Organization |> Ash.Query.filter(name == ^org_name) |> Ash.read_one!(authorize?: false)

      assert org.name == org_name
      assert org.slug == "test-org"

      # Verify membership
      membership =
        Membership
        |> Ash.Query.filter(user_id == ^user.id and organization_id == ^org.id)
        |> Ash.read_one!(authorize?: false)

      assert membership.role == :admin
    end
  end
end
