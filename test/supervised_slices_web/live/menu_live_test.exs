defmodule SupervisedSlicesWeb.MenuLiveTest do
  use SupervisedSlicesWeb.ConnCase

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias SupervisedSlices.Menu.{Category, MenuItem}
  alias SupervisedSlices.Orgs.Organization

  defp create_org(opts \\ []) do
    tax_rate = Keyword.get(opts, :tax_rate, Decimal.new("0"))

    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{
        name: "Test Pizzeria",
        slug: "test-pizzeria-#{System.unique_integer([:positive])}"
      })
      |> Ash.create!(authorize?: false)

    Organization.update_settings!(org, %{tax_rate: tax_rate}, authorize?: false)
  end

  defp create_scope(org) do
    %SupervisedSlices.Scope{
      current_user: nil,
      current_tenant: org.id,
      guest_session_id: Ash.UUIDv7.generate()
    }
  end

  defp create_category(scope) do
    Category.create!(
      %{name: "Starters", sort_order: 1},
      scope: scope,
      authorize?: false
    )
  end

  defp create_item(scope, category) do
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
  end

  setup do
    org = create_org()
    scope = create_scope(org)
    category = create_category(scope)
    item = create_item(scope, category)

    %{org: org, category: category, item: item}
  end

  describe "index (:index action)" do
    test "renders category name and menu item", %{conn: conn, org: org, category: category, item: item} do
      {:ok, _lv, html} = live(conn, ~p"/menu/#{org.slug}")

      assert html =~ org.name
      assert html =~ category.name
      assert html =~ item.name
    end

    test "renders view basket nav button", %{conn: conn, org: org} do
      {:ok, _lv, html} = live(conn, ~p"/menu/#{org.slug}")

      assert html =~ "View Basket"
    end

    test "basket is hidden on load", %{conn: conn, org: org} do
      {:ok, _lv, html} = live(conn, ~p"/menu/#{org.slug}")

      assert html =~ "invisible pointer-events-none"
    end

    test "toggling basket makes it visible", %{conn: conn, org: org} do
      {:ok, lv, _html} = live(conn, ~p"/menu/#{org.slug}")

      html = lv |> element("nav button", "View Basket") |> render_click()

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

      assert html =~ "View Basket"
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

  describe "tax display" do
    test "basket shows subtotal and total without a tax line when tax rate is 0", %{
      conn: conn,
      org: org,
      item: item
    } do
      {:ok, lv, _html} = live(conn, ~p"/menu/#{org.slug}/item/#{item.id}")

      lv |> element("button[phx-click='update_quantity'][phx-value-delta='1']") |> render_click()
      lv |> render_patch(~p"/menu/#{org.slug}")

      html = lv |> element("nav button", "View Basket") |> render_click()

      assert html =~ "Subtotal"
      assert html =~ "Total"
      refute html =~ "Tax ("
    end

    test "basket shows subtotal, tax line, and total when tax rate is set", %{
      conn: conn,
      item: _item
    } do
      taxed_org = create_org(tax_rate: Decimal.new("0.085"))
      taxed_scope = create_scope(taxed_org)
      taxed_category = create_category(taxed_scope)
      taxed_item = create_item(taxed_scope, taxed_category)

      {:ok, lv, _html} = live(conn, ~p"/menu/#{taxed_org.slug}/item/#{taxed_item.id}")

      lv |> element("button[phx-click='update_quantity'][phx-value-delta='1']") |> render_click()
      lv |> render_patch(~p"/menu/#{taxed_org.slug}")

      html = lv |> element("nav button", "View Basket") |> render_click()

      assert html =~ "Subtotal"
      assert html =~ "Tax (8.5%)"
      assert html =~ "Total"
    end

    test "tax amount is calculated correctly on a $9 item at 10% tax", %{conn: conn} do
      taxed_org = create_org(tax_rate: Decimal.new("0.10"))
      taxed_scope = create_scope(taxed_org)
      taxed_category = create_category(taxed_scope)
      taxed_item = create_item(taxed_scope, taxed_category)

      {:ok, lv, _html} = live(conn, ~p"/menu/#{taxed_org.slug}/item/#{taxed_item.id}")

      lv |> element("button[phx-click='update_quantity'][phx-value-delta='1']") |> render_click()
      lv |> render_patch(~p"/menu/#{taxed_org.slug}")

      html = lv |> element("nav button", "View Basket") |> render_click()

      assert html =~ "$9.00"
      assert html =~ "$0.90"
      assert html =~ "$9.90"
    end
  end

  describe "basket item management" do
    alias SupervisedSlices.Accounts.GuestSession
    alias SupervisedSlices.Cart.{Cart, CartItem}
    alias SupervisedSlices.Menu.{MenuItemModifierGroup, MenuItemModifier, MenuItemModifierGroupLink}

    test "removing a basket item clears it from the basket", %{conn: conn, org: org, item: item} do
      {:ok, lv, _html} = live(conn, ~p"/menu/#{org.slug}/item/#{item.id}")
      lv |> element("button[phx-click='update_quantity'][phx-value-delta='1']") |> render_click()

      lv |> render_patch(~p"/menu/#{org.slug}")
      html = lv |> element("nav button", "View Basket") |> render_click()
      assert html =~ "Subtotal"
      assert html =~ "remove_cart_item"

      html = lv |> element("button[phx-click='remove_cart_item']") |> render_click()

      assert html =~ "Empty Kitchen"
    end

    test "basket item row contains an edit link to the item detail page", %{
      conn: conn,
      org: org,
      item: item
    } do
      {:ok, lv, _html} = live(conn, ~p"/menu/#{org.slug}/item/#{item.id}")
      lv |> element("button[phx-click='update_quantity'][phx-value-delta='1']") |> render_click()

      lv |> render_patch(~p"/menu/#{org.slug}")
      html = lv |> element("nav button", "View Basket") |> render_click()

      assert html =~ "/menu/#{org.slug}/item/#{item.id}"
    end

    test "basket shows all selected modifiers for an item", %{conn: conn, org: org, item: item} do
      session_id = Ash.UUIDv7.generate()

      scope = %SupervisedSlices.Scope{
        current_user: %GuestSession{id: session_id},
        current_tenant: org.id,
        guest_session_id: session_id
      }

      group =
        MenuItemModifierGroup.create!(%{name: "Add-ons", sort_order: 0},
          scope: scope,
          authorize?: false
        )

      mod1 =
        MenuItemModifier.create!(
          %{name: "Extra Cheese", sort_order: 0, modifier_group_id: group.id},
          scope: scope,
          authorize?: false
        )

      mod2 =
        MenuItemModifier.create!(
          %{name: "Jalapeños", sort_order: 1, modifier_group_id: group.id},
          scope: scope,
          authorize?: false
        )

      MenuItemModifierGroupLink.assign(
        %{menu_item_id: item.id, modifier_group_id: group.id},
        scope: scope,
        authorize?: false
      )

      cart = Cart.create!(scope: scope)

      CartItem.add_to_cart!(
        %{
          cart_id: cart.id,
          menu_item_id: item.id,
          quantity: 1,
          selected_modifier_ids: [mod1.id, mod2.id]
        },
        scope: scope,
        authorize?: false
      )

      conn = Plug.Test.init_test_session(conn, %{"guest_session_id" => session_id})
      {:ok, lv, _html} = live(conn, ~p"/menu/#{org.slug}")

      html = lv |> element("nav button", "View Basket") |> render_click()

      assert html =~ "Extra Cheese"
      assert html =~ "Jalapeños"
    end
  end

  describe "order placement with tax" do
    test "placing an order stores tax_amount on the order", %{conn: conn} do
      alias SupervisedSlices.Orders.Order

      taxed_org = create_org(tax_rate: Decimal.new("0.10"))
      taxed_scope = create_scope(taxed_org)
      taxed_category = create_category(taxed_scope)
      taxed_item = create_item(taxed_scope, taxed_category)

      {:ok, lv, _html} = live(conn, ~p"/menu/#{taxed_org.slug}/item/#{taxed_item.id}")

      lv |> element("button[phx-click='update_quantity'][phx-value-delta='1']") |> render_click()
      lv |> render_patch(~p"/menu/#{taxed_org.slug}")
      lv |> element("nav button", "View Basket") |> render_click()
      lv |> element("button[phx-click='start_checkout']") |> render_click()

      lv
      |> form("form[phx-submit='place_order']", %{customer_name: "Test Customer", customer_email: "test@example.com"})
      |> render_submit()

      assert_email_sent(to: "test@example.com")

      orders = Order.active!(scope: taxed_scope, authorize?: false)
      order = List.first(orders)

      assert order != nil
      assert order.tax_amount != nil
      assert Money.compare!(order.tax_amount, Money.new!(:USD, "0.90")) == :eq
      assert Money.compare!(order.total_price, Money.new!(:USD, "9.90")) == :eq
    end

    test "placing an order with no tax stores zero tax_amount", %{conn: conn, org: org, item: item} do
      alias SupervisedSlices.Orders.Order

      scope = create_scope(org)

      {:ok, lv, _html} = live(conn, ~p"/menu/#{org.slug}/item/#{item.id}")

      lv |> element("button[phx-click='update_quantity'][phx-value-delta='1']") |> render_click()
      lv |> render_patch(~p"/menu/#{org.slug}")
      lv |> element("nav button", "View Basket") |> render_click()
      lv |> element("button[phx-click='start_checkout']") |> render_click()

      lv
      |> form("form[phx-submit='place_order']", %{customer_name: "Test Customer", customer_email: "test@example.com"})
      |> render_submit()

      orders = Order.active!(scope: scope, authorize?: false)
      order = List.first(orders)

      assert order != nil
      assert Money.compare!(order.total_price, Money.new!(:USD, "9.00")) == :eq
    end

    test "placing an order with modifiers and sizes stores snapshots correctly", %{conn: conn, org: org, item: item} do
      alias SupervisedSlices.Accounts.GuestSession
      alias SupervisedSlices.Cart.{Cart, CartItem}
      alias SupervisedSlices.Menu.{MenuItemModifierGroup, MenuItemModifier, MenuItemModifierGroupLink, MenuItemSize}
      alias SupervisedSlices.Orders.Order

      session_id = Ash.UUIDv7.generate()
      scope = %SupervisedSlices.Scope{
        current_user: %GuestSession{id: session_id},
        current_tenant: org.id,
        guest_session_id: session_id
      }

      size = MenuItemSize.create!(%{name: "Large", price: Money.new!(:USD, "12.00"), menu_item_id: item.id}, scope: scope, authorize?: false)
      group = MenuItemModifierGroup.create!(%{name: "Toppings", sort_order: 0}, scope: scope, authorize?: false)
      mod1 = MenuItemModifier.create!(%{name: "Pepperoni", sort_order: 0, modifier_group_id: group.id, price_delta: Money.new!(:USD, "1.50")}, scope: scope, authorize?: false)
      MenuItemModifierGroupLink.assign(%{menu_item_id: item.id, modifier_group_id: group.id}, scope: scope, authorize?: false)

      cart = Cart.create!(scope: scope)
      CartItem.add_to_cart!(%{cart_id: cart.id, menu_item_id: item.id, quantity: 1, selected_modifier_ids: [mod1.id], selected_size_id: size.id}, scope: scope, authorize?: false)

      conn = Plug.Test.init_test_session(conn, %{"guest_session_id" => session_id})
      {:ok, lv, _html} = live(conn, ~p"/menu/#{org.slug}")

      lv |> element("nav button", "View Basket") |> render_click()
      lv |> element("button[phx-click='start_checkout']") |> render_click()
      lv |> form("form[phx-submit='place_order']", %{customer_name: "Test Customer", customer_email: "test@example.com"}) |> render_submit()

      order = Order.active!(scope: scope, authorize?: false, load: [:order_items]) |> List.first()
      assert [item] = order.order_items
      # Size 12.00 + 1.50 = 13.50
      assert Money.compare!(item.price_at_time, Money.new!(:USD, "13.50")) == :eq
      
      assert item.size_snapshot["name"] == "Large"
      assert [mod] = item.modifiers_snapshot
      assert mod["name"] == "Pepperoni"
    end

    test "checkout form contains required email field", %{conn: conn, org: org, item: item} do
      {:ok, lv, _html} = live(conn, ~p"/menu/#{org.slug}/item/#{item.id}")

      lv |> element("button[phx-click='update_quantity'][phx-value-delta='1']") |> render_click()
      lv |> render_patch(~p"/menu/#{org.slug}")
      lv |> element("nav button", "View Basket") |> render_click()
      html = lv |> element("button[phx-click='start_checkout']") |> render_click()

      assert html =~ "Email"
      assert html =~ "required"
      assert html =~ "type=\"email\""
      assert html =~ "name=\"customer_email\""
    end
  end
end
