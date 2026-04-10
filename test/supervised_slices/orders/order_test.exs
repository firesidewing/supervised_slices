defmodule SupervisedSlices.Orders.OrderTest do
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

  setup do
    %{org: create_org()}
  end

  describe "place_order" do
    test "requires customer_email", %{org: org} do
      result =
        Order.place_order(
          %{
            customer_name: "Test Customer",
            total_price: Money.new!(:CAD, "10.00"),
            tax_amount: Money.new!(:CAD, "0.85")
          },
          tenant: org.id,
          authorize?: false
        )

      assert {:error, %Ash.Error.Invalid{errors: [error]}} = result
      assert error.field == :customer_email
    end

    test "allows customer_phone to be nil", %{org: org} do
      result =
        Order.place_order(
          %{
            customer_name: "Test Customer",
            customer_email: "test@example.com",
            customer_phone: nil,
            total_price: Money.new!(:CAD, "10.00"),
            tax_amount: Money.new!(:CAD, "0.85")
          },
          tenant: org.id,
          authorize?: false
        )

      assert {:ok, order} = result
      assert order.customer_email == "test@example.com"
      assert order.customer_phone == nil
    end

    test "accepts customer_phone when provided", %{org: org} do
      result =
        Order.place_order(
          %{
            customer_name: "Test Customer",
            customer_email: "test@example.com",
            customer_phone: "555-1234",
            total_price: Money.new!(:CAD, "10.00"),
            tax_amount: Money.new!(:CAD, "0.85")
          },
          tenant: org.id,
          authorize?: false
        )

      assert {:ok, order} = result
      assert order.customer_email == "test@example.com"
      assert order.customer_phone == "555-1234"
    end
  end
end
