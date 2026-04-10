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
        customer_email: "alice@example.com",
        total_price: Money.new!(:CAD, "15.00"),
        tax_amount: Money.new!(:CAD, "0.00")
      },
      tenant: org.id,
      authorize?: false
    )
  end

  # Helper for creating OrderUpdate records in tests. Uses the raw Ash API
  # since create is intentionally not exposed via code_interface (system-internal).
  defp create_update(params, org) do
    OrderUpdate
    |> Ash.Changeset.for_create(:create, params)
    |> Ash.create!(tenant: org.id, authorize?: false)
  end

  setup do
    org = create_org()
    order = create_order(org)
    %{org: org, order: order}
  end

  describe "create (internal)" do
    test "creates an update with a status", %{org: org, order: order} do
      update = create_update(%{order_id: order.id, status: :confirmed}, org)

      assert update.status == :confirmed
      assert update.message == nil
      assert update.order_id == order.id
    end

    test "creates an update with a message", %{org: org, order: order} do
      update = create_update(%{order_id: order.id, message: "Ready in ~5 min"}, org)

      assert update.message == "Ready in ~5 min"
      assert update.status == nil
    end

    test "creates an update with both status and message", %{org: org, order: order} do
      update =
        create_update(%{order_id: order.id, status: :preparing, message: "Starting now"}, org)

      assert update.status == :preparing
      assert update.message == "Starting now"
    end

    test "create is forbidden for external callers (with an actor)", %{org: org, order: order} do
      actor = %SupervisedSlices.Accounts.User{
        id: Ash.UUIDv7.generate(),
        email: "test@example.com"
      }

      result =
        OrderUpdate
        |> Ash.Changeset.for_create(:create, %{order_id: order.id, status: :confirmed})
        |> Ash.create(tenant: org.id, actor: actor)

      assert {:error, %Ash.Error.Forbidden{}} = result
    end
  end

  describe "for_order/2" do
    test "returns updates for the correct order in chronological order", %{org: org, order: order} do
      create_update(%{order_id: order.id, status: :confirmed}, org)
      create_update(%{order_id: order.id, message: "Running behind"}, org)
      create_update(%{order_id: order.id, status: :preparing}, org)

      updates = OrderUpdate.for_order!(order.id, tenant: org.id, authorize?: false)

      assert length(updates) == 3
      assert Enum.map(updates, & &1.status) == [:confirmed, nil, :preparing]
    end

    test "does not return updates from other orders", %{org: org, order: order} do
      other_order = create_order(org)

      create_update(%{order_id: order.id, status: :confirmed}, org)
      create_update(%{order_id: other_order.id, status: :preparing}, org)

      updates = OrderUpdate.for_order!(order.id, tenant: org.id, authorize?: false)
      assert length(updates) == 1
      assert hd(updates).status == :confirmed
    end
  end
end
