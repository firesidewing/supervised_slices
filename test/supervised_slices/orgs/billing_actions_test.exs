defmodule SupervisedSlices.Orgs.OrganizationBillingTest do
  use SupervisedSlices.DataCase, async: true
  alias SupervisedSlices.Orgs.Organization

  describe "update_billing action" do
    test "updates billing fields correctly" do
      org =
        Organization
        |> Ash.Changeset.for_create(:create, %{name: "Test Org"})
        |> Ash.create!(authorize?: false)

      updated_org =
        org
        |> Ash.Changeset.for_update(:update_billing, %{
          stripe_customer_id: "cus_123",
          stripe_subscription_id: "sub_456",
          subscription_status: :active
        })
        |> Ash.update!(authorize?: false)

      assert updated_org.stripe_customer_id == "cus_123"
      assert updated_org.stripe_subscription_id == "sub_456"
      assert updated_org.subscription_status == :active
    end
  end

  describe "subscribed? calculation" do
    test "returns true for active and trialing statuses" do
      org_active =
        Organization
        |> Ash.Changeset.for_create(:create, %{name: "Active"})
        |> Ash.create!(authorize?: false)
        |> Ash.Changeset.for_update(:update_billing, %{subscription_status: :active})
        |> Ash.update!(authorize?: false)

      org_trialing =
        Organization
        |> Ash.Changeset.for_create(:create, %{name: "Trialing"})
        |> Ash.create!(authorize?: false)
        |> Ash.Changeset.for_update(:update_billing, %{subscription_status: :trialing})
        |> Ash.update!(authorize?: false)

      assert Ash.load!(org_active, :subscribed?).subscribed?
      assert Ash.load!(org_trialing, :subscribed?).subscribed?
    end

    test "returns false for other statuses" do
      org_none =
        Organization
        |> Ash.Changeset.for_create(:create, %{name: "None"})
        |> Ash.create!(authorize?: false)

      org_canceled =
        Organization
        |> Ash.Changeset.for_create(:create, %{name: "Canceled"})
        |> Ash.create!(authorize?: false)
        |> Ash.Changeset.for_update(:update_billing, %{subscription_status: :canceled})
        |> Ash.update!(authorize?: false)

      org_past_due =
        Organization
        |> Ash.Changeset.for_create(:create, %{name: "Past Due"})
        |> Ash.create!(authorize?: false)
        |> Ash.Changeset.for_update(:update_billing, %{subscription_status: :past_due})
        |> Ash.update!(authorize?: false)

      refute Ash.load!(org_none, :subscribed?).subscribed?
      refute Ash.load!(org_canceled, :subscribed?).subscribed?
      refute Ash.load!(org_past_due, :subscribed?).subscribed?
    end
  end
end
