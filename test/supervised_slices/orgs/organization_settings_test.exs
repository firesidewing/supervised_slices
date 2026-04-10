defmodule SupervisedSlices.Orgs.OrganizationSettingsTest do
  use SupervisedSlices.DataCase, async: true

  alias SupervisedSlices.Orgs.Organization

  defp create_org do
    Organization
    |> Ash.Changeset.for_create(:create, %{
      name: "Test Kitchen",
      slug: "test-kitchen-#{System.unique_integer([:positive])}"
    })
    |> Ash.create!(authorize?: false)
  end

  describe "update_settings/2" do
    test "persists default_prep_time" do
      org = create_org()
      assert org.default_prep_time == 20

      updated = Organization.update_settings!(org, %{default_prep_time: 35}, authorize?: false)
      assert updated.default_prep_time == 35
    end

    test "persists tax_rate alongside default_prep_time" do
      org = create_org()

      updated =
        Organization.update_settings!(
          org,
          %{tax_rate: Decimal.new("0.08"), default_prep_time: 15},
          authorize?: false
        )

      assert updated.default_prep_time == 15
      assert Decimal.equal?(updated.tax_rate, Decimal.new("0.08"))
    end

    test "new orgs default to 20 minute prep time" do
      org = create_org()
      assert org.default_prep_time == 20
    end
  end
end
