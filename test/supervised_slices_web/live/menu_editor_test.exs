defmodule SupervisedSlicesWeb.MenuEditorTest do
  use SupervisedSlicesWeb.ConnCase
  import Phoenix.LiveViewTest

  alias SupervisedSlices.Accounts.User
  alias SupervisedSlices.Orgs.{Organization, Membership}
  alias SupervisedSlices.Menu.{Category, MenuItemModifierGroup, MenuItemModifier}

  require Ash.Query

  # ---------------------------------------------------------------------------
  # Test setup helpers
  # ---------------------------------------------------------------------------

  defp register_admin_user do
    unique = System.unique_integer([:positive])

    User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: "admin#{unique}@example.com",
      organization_name: "Test Kitchen #{unique}",
      password: "password123",
      password_confirmation: "password123"
    })
    |> Ash.create!(authorize?: false)
  end

  defp get_admin_org(user) do
    user_id = user.id

    Membership
    |> Ash.Query.filter(user_id == ^user_id and role == :admin)
    |> Ash.read_one!(authorize?: false, load: [:organization])
    |> Map.get(:organization)
  end

  defp activate_org(org) do
    Organization.update_billing!(
      org,
      %{subscription_status: :trialing},
      authorize?: false
    )
  end

  defp log_in(conn, user) do
    token = user.__metadata__.token
    Plug.Test.init_test_session(conn, %{"user_token" => token})
  end

  defp create_scope(org) do
    %SupervisedSlices.Scope{
      current_user: nil,
      current_tenant: org.id,
      guest_session_id: nil
    }
  end

  defp create_category(scope) do
    Category.create!(%{name: "Mains", sort_order: 0}, scope: scope, authorize?: false)
  end

  defp create_modifier_group(scope, attrs) do
    MenuItemModifierGroup.create!(
      Map.merge(%{name: "Sauces", sort_order: 0}, attrs),
      scope: scope,
      authorize?: false
    )
  end

  defp create_modifier(scope, group, attrs) do
    MenuItemModifier.create!(
      Map.merge(%{name: "Ranch", sort_order: 0, modifier_group_id: group.id}, attrs),
      scope: scope,
      authorize?: false
    )
  end

  setup do
    user = register_admin_user()
    org = user |> get_admin_org() |> activate_org()
    scope = create_scope(org)
    _category = create_category(scope)

    %{user: user, org: org, scope: scope}
  end

  # ---------------------------------------------------------------------------
  # Sidebar renders groups
  # ---------------------------------------------------------------------------

  describe "modifier groups sidebar" do
    test "shows empty state when no groups exist", %{conn: conn, user: user, org: org} do
      conn = log_in(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      assert html =~ "No modifier groups yet"
    end

    test "shows existing groups in sidebar", %{conn: conn, user: user, org: org, scope: scope} do
      create_modifier_group(scope, %{name: "Toppings"})
      conn = log_in(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      assert html =~ "Toppings"
    end

    test "shows required badge for required groups", %{
      conn: conn,
      user: user,
      org: org,
      scope: scope
    } do
      create_modifier_group(scope, %{name: "Protein", required: true})
      conn = log_in(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      assert html =~ "Req."
    end

    test "shows max badge when max_selections is set", %{
      conn: conn,
      user: user,
      org: org,
      scope: scope
    } do
      create_modifier_group(scope, %{name: "Drinks", max_selections: 2})
      conn = log_in(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      assert html =~ "max 2"
    end
  end

  # ---------------------------------------------------------------------------
  # Drawer open/close
  # ---------------------------------------------------------------------------

  describe "modifier group drawer" do
    test "group drawer is hidden on load", %{conn: conn, user: user, org: org} do
      conn = log_in(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      assert has_element?(lv, "#group-drawer-wrapper.invisible")
    end

    test "clicking New Group opens group drawer", %{conn: conn, user: user, org: org} do
      conn = log_in(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      lv |> element("button[phx-click='add_modifier_group']") |> render_click()

      refute has_element?(lv, "#group-drawer-wrapper.invisible")
      assert has_element?(lv, "h2", "New Group")
    end

    test "clicking an existing group row opens drawer with group name", %{
      conn: conn,
      user: user,
      org: org,
      scope: scope
    } do
      create_modifier_group(scope, %{name: "Extra Cheese"})
      conn = log_in(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      lv |> element("button[phx-click='open_in_drawer']") |> render_click()

      refute has_element?(lv, "#group-drawer-wrapper.invisible")
      assert has_element?(lv, "h2", "Extra Cheese")
    end

    test "backdrop click closes drawer", %{conn: conn, user: user, org: org} do
      conn = log_in(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      lv |> element("button[phx-click='add_modifier_group']") |> render_click()
      lv |> element("div[phx-click='cancel_group_edit']") |> render_click()

      assert has_element?(lv, "#group-drawer-wrapper.invisible")
    end
  end

  # ---------------------------------------------------------------------------
  # Creating groups
  # ---------------------------------------------------------------------------

  describe "creating modifier groups" do
    test "submitting the new group form creates the group and stays open", %{
      conn: conn,
      user: user,
      org: org
    } do
      conn = log_in(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      lv |> element("button[phx-click='add_modifier_group']") |> render_click()

      lv
      |> form("#group-form", %{"group" => %{"name" => "Sauces"}})
      |> render_submit()

      assert has_element?(lv, "h2", "Sauces")
    end

    test "new group appears in sidebar after creation", %{conn: conn, user: user, org: org} do
      conn = log_in(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      lv |> element("button[phx-click='add_modifier_group']") |> render_click()

      lv
      |> form("#group-form", %{"group" => %{"name" => "Dressings"}})
      |> render_submit()

      html = render(lv)
      assert html =~ "Dressings"
    end
  end

  # ---------------------------------------------------------------------------
  # Editing groups
  # ---------------------------------------------------------------------------

  describe "editing modifier groups" do
    test "saving group form updates the group name", %{
      conn: conn,
      user: user,
      org: org,
      scope: scope
    } do
      create_modifier_group(scope, %{name: "Old Name"})
      conn = log_in(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      lv |> element("button[phx-click='open_in_drawer']") |> render_click()

      html =
        lv
        |> form("#group-form", %{"group" => %{"name" => "New Name"}})
        |> render_submit()

      assert html =~ "New Name"
    end
  end

  # ---------------------------------------------------------------------------
  # Deleting groups
  # ---------------------------------------------------------------------------

  describe "deleting modifier groups" do
    test "clicking Delete Group shows confirmation", %{
      conn: conn,
      user: user,
      org: org,
      scope: scope
    } do
      create_modifier_group(scope, %{name: "To Delete"})
      conn = log_in(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      lv |> element("button[phx-click='open_in_drawer']") |> render_click()

      html =
        lv
        |> element("button[phx-click='delete_group']")
        |> render_click()

      assert html =~ "This cannot be undone"
    end

    test "confirming delete removes the group and closes drawer", %{
      conn: conn,
      user: user,
      org: org,
      scope: scope
    } do
      create_modifier_group(scope, %{name: "Gone Group"})
      conn = log_in(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      lv |> element("button[phx-click='open_in_drawer']") |> render_click()
      lv |> element("button[phx-click='delete_group']") |> render_click()

      html =
        lv
        |> element("button[phx-click='confirm_delete_group']")
        |> render_click()

      assert html =~ "invisible pointer-events-none"
      refute html =~ "Gone Group"
    end
  end

  # ---------------------------------------------------------------------------
  # Adding modifiers
  # ---------------------------------------------------------------------------

  describe "adding modifiers to a group" do
    test "clicking Add option shows the add form", %{
      conn: conn,
      user: user,
      org: org,
      scope: scope
    } do
      create_modifier_group(scope, %{name: "Toppings"})
      conn = log_in(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      lv |> element("button[phx-click='open_in_drawer']") |> render_click()

      html =
        lv
        |> element("button[phx-click='add_modifier']")
        |> render_click()

      assert html =~ "Option name"
    end

    test "submitting add option form creates a modifier", %{
      conn: conn,
      user: user,
      org: org,
      scope: scope
    } do
      create_modifier_group(scope, %{name: "Extras"})
      conn = log_in(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      lv |> element("button[phx-click='open_in_drawer']") |> render_click()
      lv |> element("button[phx-click='add_modifier']") |> render_click()

      html =
        lv
        |> form("form[phx-submit='create_modifier']", %{
          "modifier" => %{"name" => "Jalapeños", "price_delta" => "0.50"}
        })
        |> render_submit()

      assert html =~ "Jalapeños"
      assert html =~ "+CA$0.50"
    end
  end

  # ---------------------------------------------------------------------------
  # Editing modifiers inline
  # ---------------------------------------------------------------------------

  describe "inline modifier editing" do
    test "clicking edit on a modifier shows the edit form", %{
      conn: conn,
      user: user,
      org: org,
      scope: scope
    } do
      group = create_modifier_group(scope, %{name: "Sauces"})
      create_modifier(scope, group, %{name: "BBQ"})
      conn = log_in(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      lv |> element("button[phx-click='open_in_drawer']") |> render_click()

      html =
        lv
        |> element("button[phx-click='edit_modifier']")
        |> render_click()

      assert html =~ "Price Add-on"
      assert html =~ "Available"
    end

    test "saving modifier edit updates name and price", %{
      conn: conn,
      user: user,
      org: org,
      scope: scope
    } do
      group = create_modifier_group(scope, %{name: "Sauces"})
      mod = create_modifier(scope, group, %{name: "Old Sauce"})
      conn = log_in(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      lv |> element("button[phx-click='open_in_drawer']") |> render_click()
      lv |> element("button[phx-click='edit_modifier']") |> render_click()

      html =
        lv
        |> form("form[phx-submit='save_modifier']", %{
          "modifier" => %{"id" => mod.id, "name" => "New Sauce", "price_delta" => "0.75"}
        })
        |> render_submit()

      assert html =~ "New Sauce"
      assert html =~ "+CA$0.75"
    end
  end

  # ---------------------------------------------------------------------------
  # Deleting modifiers
  # ---------------------------------------------------------------------------

  describe "deleting modifiers" do
    test "clicking delete on a modifier removes it from the list", %{
      conn: conn,
      user: user,
      org: org,
      scope: scope
    } do
      group = create_modifier_group(scope, %{name: "Sauces"})
      create_modifier(scope, group, %{name: "Ranch"})
      conn = log_in(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      lv |> element("button[phx-click='open_in_drawer']") |> render_click()

      html =
        lv
        |> element("button[phx-click='delete_modifier']")
        |> render_click()

      refute html =~ "Ranch"
    end
  end

  # ---------------------------------------------------------------------------
  # Available toggle
  # ---------------------------------------------------------------------------

  describe "modifier availability toggle" do
    test "toggling availability changes the modifier's visual state", %{
      conn: conn,
      user: user,
      org: org,
      scope: scope
    } do
      group = create_modifier_group(scope, %{name: "Sides"})
      create_modifier(scope, group, %{name: "Fries"})
      conn = log_in(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/kitchen/#{org.slug}/menu")

      lv |> element("button[phx-click='open_in_drawer']") |> render_click()

      html =
        lv
        |> element("button[phx-click='toggle_modifier_available']")
        |> render_click()

      assert html =~ "line-through"
    end
  end
end
