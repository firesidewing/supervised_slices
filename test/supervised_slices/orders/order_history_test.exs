defmodule SupervisedSlices.Orders.OrderHistoryTest do
  use SupervisedSlices.DataCase, async: true

  alias SupervisedSlices.Orders.Order
  alias SupervisedSlices.Orgs.Organization

  defp create_org do
    Organization
    |> Ash.Changeset.for_create(:create, %{
      name: "Test Kitchen",
      slug: "test-kitchen-#{System.unique_integer([:positive])}"
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_order(org) do
    Order.place_order!(
      %{
        customer_name: "Alice",
        customer_email: "alice@example.com",
        total_price: Money.new!(:CAD, "25.00"),
        tax_amount: Money.new!(:CAD, "0.00")
      },
      tenant: org.id,
      authorize?: false
    )
  end

  setup do
    org = create_org()
    %{org: org}
  end

  describe "completed_orders read action" do
    test "returns only completed and cancelled orders", %{org: org} do
      order = create_order(org)
      _active = create_order(org)

      Order.update_status!(order, %{status: :completed}, tenant: org.id, authorize?: false)

      results = Order.completed_orders!(tenant: org.id, authorize?: false)
      assert length(results) == 1
      assert hd(results).id == order.id
    end

    test "excludes active orders in all states", %{org: org} do
      order = create_order(org)

      for status <- [:confirmed, :preparing, :ready] do
        Order.update_status!(order, %{status: status}, tenant: org.id, authorize?: false)
      end

      results = Order.completed_orders!(tenant: org.id, authorize?: false)
      assert results == []
    end

    test "includes cancelled orders", %{org: org} do
      order = create_order(org)
      Order.update_status!(order, %{status: :cancelled}, tenant: org.id, authorize?: false)

      results = Order.completed_orders!(tenant: org.id, authorize?: false)
      assert length(results) == 1
      assert hd(results).status == :cancelled
    end

    test "returns orders sorted newest first", %{org: org} do
      first = create_order(org)
      second = create_order(org)

      Order.update_status!(first, %{status: :completed}, tenant: org.id, authorize?: false)
      Order.update_status!(second, %{status: :completed}, tenant: org.id, authorize?: false)

      results = Order.completed_orders!(tenant: org.id, authorize?: false)
      ids = Enum.map(results, & &1.id)

      # Newest (second) should come first
      assert ids == [second.id, first.id]
    end

    test "loads order_items", %{org: org} do
      order = create_order(org)
      Order.update_status!(order, %{status: :completed}, tenant: org.id, authorize?: false)

      [result] = Order.completed_orders!(tenant: org.id, authorize?: false)
      assert is_list(result.order_items)
      refute match?(%Ash.NotLoaded{}, result.order_items)
    end
  end
end
