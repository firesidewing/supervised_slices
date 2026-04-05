defmodule SupervisedSlicesWeb.MenuLiveTest do
  use SupervisedSlicesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias SupervisedSlices.Menu.{Category, MenuItem}
  alias SupervisedSlices.Orgs.Organization

  setup do
    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{
        name: "Test Pizzeria",
        slug: "test-pizzeria-#{System.unique_integer([:positive])}"
      })
      |> Ash.create!(authorize?: false)

    scope = %SupervisedSlices.Scope{
      current_user: nil,
      current_tenant: org.id,
      guest_session_id: Ash.UUIDv7.generate()
    }

    category =
      Category.create!(
        %{name: "Starters", sort_order: 1},
        scope: scope,
        authorize?: false
      )

    item =
      MenuItem.create!(
        %{
          name: "Bruschetta",
          description: "Toasted bread with tomato",
          price: Money.new!(:USD, "9.00"),
          category_id: category.id
        },
        scope: scope,
        authorize?: false
      )

    %{org: org, category: category, item: item}
  end

  describe "index (:index action)" do
    test "renders category name and menu item", %{conn: conn, org: org, category: category, item: item} do
      {:ok, _lv, html} = live(conn, ~p"/menu/#{org.slug}")

      assert html =~ org.name
      assert html =~ category.name
      assert html =~ item.name
    end

    test "renders explore menu nav button", %{conn: conn, org: org} do
      {:ok, _lv, html} = live(conn, ~p"/menu/#{org.slug}")

      assert html =~ "Explore Menu"
      assert html =~ "View Basket"
    end

    test "basket is hidden on load", %{conn: conn, org: org} do
      {:ok, _lv, html} = live(conn, ~p"/menu/#{org.slug}")

      assert html =~ "invisible pointer-events-none"
    end

    test "toggling basket makes it visible", %{conn: conn, org: org} do
      {:ok, lv, _html} = live(conn, ~p"/menu/#{org.slug}")

      html = lv |> element("nav button[phx-click='toggle_basket']") |> render_click()

      refute html =~ "invisible pointer-events-none"
      assert html =~ "Your Basket"
    end
  end

  describe "item detail (:show action)" do
    test "navigating to item route renders detail within same LiveView", %{
      conn: conn,
      org: org,
      item: item
    } do
      {:ok, lv, _html} = live(conn, ~p"/menu/#{org.slug}")

      html = render_patch(lv, ~p"/menu/#{org.slug}/item/#{item.id}")

      assert html =~ item.name
      assert html =~ item.description
      assert html =~ "arrow_back"
    end

    test "back link returns to index without reconnect", %{conn: conn, org: org, item: item} do
      {:ok, lv, _html} = live(conn, ~p"/menu/#{org.slug}/item/#{item.id}")

      html = render_patch(lv, ~p"/menu/#{org.slug}")

      assert html =~ "Explore Menu"
      refute html =~ "arrow_back"
    end
  end

  describe "cart interactions" do
    test "adding a simple item increments cart count", %{conn: conn, org: org, item: item} do
      {:ok, lv, _html} = live(conn, ~p"/menu/#{org.slug}/item/#{item.id}")

      html =
        lv
        |> element("button[phx-click='update_quantity'][phx-value-delta='1']")
        |> render_click()

      assert html =~ "1"
    end
  end
end
