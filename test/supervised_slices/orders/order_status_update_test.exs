defmodule SupervisedSlices.Orders.OrderStatusUpdateTest do
  use SupervisedSlices.DataCase, async: true

  alias SupervisedSlices.Orders.{Order, OrderUpdate}
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
        customer_name: "Bob",
        customer_email: "bob@example.com",
        total_price: Money.new!(:CAD, "20.00"),
        tax_amount: Money.new!(:CAD, "0.00")
      },
      tenant: org.id,
      authorize?: false
    )
  end

  setup do
    org = create_org()
    order = create_order(org)
    %{org: org, order: order}
  end

  describe "update_status/2" do
    test "advancing status creates an OrderUpdate record", %{org: org, order: order} do
      Order.update_status!(order, %{status: :confirmed},
        tenant: org.id,
        authorize?: false
      )

      updates = OrderUpdate.for_order!(order.id, tenant: org.id, authorize?: false)
      assert length(updates) == 1
      assert hd(updates).status == :confirmed
    end

    test "multiple status transitions create multiple OrderUpdates", %{org: org, order: order} do
      order =
        Order.update_status!(order, %{status: :confirmed}, tenant: org.id, authorize?: false)

      order =
        Order.update_status!(order, %{status: :preparing}, tenant: org.id, authorize?: false)

      Order.update_status!(order, %{status: :ready}, tenant: org.id, authorize?: false)

      updates = OrderUpdate.for_order!(order.id, tenant: org.id, authorize?: false)
      assert length(updates) == 3
      assert Enum.map(updates, & &1.status) == [:confirmed, :preparing, :ready]
    end

    test "update_status broadcasts to PubSub", %{org: org, order: order} do
      Phoenix.PubSub.subscribe(SupervisedSlices.PubSub, "orders:#{org.id}:#{order.id}")

      Order.update_status!(order, %{status: :confirmed}, tenant: org.id, authorize?: false)

      assert_receive {:order_status, updated_order}
      assert updated_order.status == :confirmed
    end
  end
end
