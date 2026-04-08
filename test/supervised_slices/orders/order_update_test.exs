defmodule SupervisedSlices.Orders.OrderUpdateTest do
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
        customer_name: "Alice",
        total_price: Money.new!(:USD, "15.00"),
        tax_amount: Money.new!(:USD, "0.00")
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

  describe "create/2" do
    test "creates an update with a status", %{org: org, order: order} do
      assert {:ok, update} =
               OrderUpdate.create(
                 %{order_id: order.id, status: :confirmed},
                 tenant: org.id,
                 authorize?: false
               )

      assert update.status == :confirmed
      assert update.message == nil
      assert update.order_id == order.id
    end

    test "creates an update with a message", %{org: org, order: order} do
      assert {:ok, update} =
               OrderUpdate.create(
                 %{order_id: order.id, message: "Ready in ~5 min"},
                 tenant: org.id,
                 authorize?: false
               )

      assert update.message == "Ready in ~5 min"
      assert update.status == nil
    end

    test "creates an update with both status and message", %{org: org, order: order} do
      assert {:ok, update} =
               OrderUpdate.create(
                 %{order_id: order.id, status: :preparing, message: "Starting now"},
                 tenant: org.id,
                 authorize?: false
               )

      assert update.status == :preparing
      assert update.message == "Starting now"
    end
  end

  describe "for_order/2" do
    test "returns updates for the correct order in chronological order", %{org: org, order: order} do
      {:ok, _} =
        OrderUpdate.create(%{order_id: order.id, status: :confirmed},
          tenant: org.id,
          authorize?: false
        )

      {:ok, _} =
        OrderUpdate.create(%{order_id: order.id, message: "Running behind"},
          tenant: org.id,
          authorize?: false
        )

      {:ok, _} =
        OrderUpdate.create(%{order_id: order.id, status: :preparing},
          tenant: org.id,
          authorize?: false
        )

      updates = OrderUpdate.for_order!(order.id, tenant: org.id, authorize?: false)

      assert length(updates) == 3
      statuses = Enum.map(updates, & &1.status)
      assert statuses == [:confirmed, nil, :preparing]
    end

    test "does not return updates from other orders", %{org: org, order: order} do
      other_order = create_order(org)

      {:ok, _} =
        OrderUpdate.create(%{order_id: order.id, status: :confirmed},
          tenant: org.id,
          authorize?: false
        )

      {:ok, _} =
        OrderUpdate.create(%{order_id: other_order.id, status: :preparing},
          tenant: org.id,
          authorize?: false
        )

      updates = OrderUpdate.for_order!(order.id, tenant: org.id, authorize?: false)
      assert length(updates) == 1
      assert hd(updates).status == :confirmed
    end
  end
end
