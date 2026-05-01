defmodule SupervisedSlices.Orgs.OrganizationSlugTest do
  use SupervisedSlices.DataCase, async: true

  alias SupervisedSlices.Orgs.Organization

  defp create_org(name) do
    Organization
    |> Ash.Changeset.for_create(:create, %{name: name})
    |> Ash.create!(authorize?: false)
  end

  describe "slug auto-generation" do
    test "slug is generated from name with UUID suffix" do
      org = create_org("My Restaurant")
      assert org.slug =~ ~r/^my-restaurant-[0-9a-f]{6}$/
    end

    test "two orgs with the same name get different slugs" do
      first = create_org("My Restaurant")
      second = create_org("My Restaurant")
      refute first.slug == second.slug
    end

    test "names that produce the same base slug get different slugs" do
      first = create_org("My Restaurant")
      second = create_org("My-Restaurant")
      refute first.slug == second.slug
    end

    test "explicitly provided slug is used as-is" do
      org =
        Organization
        |> Ash.Changeset.for_create(:create, %{name: "My Restaurant", slug: "custom-slug"})
        |> Ash.create!(authorize?: false)

      assert org.slug == "custom-slug"
    end
  end
end
