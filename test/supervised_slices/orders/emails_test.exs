defmodule SupervisedSlices.Orders.EmailsTest do
  use SupervisedSlices.DataCase, async: true

  alias SupervisedSlices.Orders.{Order, OrderItem, Emails}
  alias SupervisedSlices.Orgs.Organization

  setup do
    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "Pizza Heaven", slug: "pizza-heaven"})
      |> Ash.create!(authorize?: false)

    order =
      Order.place_order!(
        %{
          customer_name: "John Doe",
          customer_email: "john@example.com",
          total_price: Money.new!(:USD, "25.00"),
          tax_amount: Money.new!(:USD, "2.12"),
          notes: "Please leave at the door."
        },
        tenant: org.id,
        authorize?: false
      )

    # Add items to the order
    OrderItem.create!(
      %{
        order_id: order.id,
        quantity: 2,
        item_name: "Margherita Pizza",
        price_at_time: Money.new!(:USD, "10.00"),
        size_snapshot: %{"name" => "Large"}
      },
      tenant: org.id,
      authorize?: false
    )

    OrderItem.create!(
      %{
        order_id: order.id,
        quantity: 1,
        item_name: "Garlic Bread",
        price_at_time: Money.new!(:USD, "5.00"),
        modifiers_snapshot: [%{"name" => "Extra Cheese"}]
      },
      tenant: org.id,
      authorize?: false
    )

    %{org: org, order: order}
  end

  test "send_order_confirmation/1 delivers an email with correct content", %{order: order} do
    # Reload order to ensure everything is ready
    order = Ash.get!(Order, order.id, tenant: order.organization_id, authorize?: false)
    
    Emails.send_order_confirmation(order)

    assert_receive {:email, email}
    assert email.from == {"Supervised Slices", "noreply@supervisedslices.com"}
    assert email.to == [{"", "john@example.com"}]
    assert email.subject == "Order Confirmation ##{String.slice(order.id, -4, 4) |> String.upcase()} - Pizza Heaven"
    assert email.html_body =~ "Pizza Heaven"
    assert email.html_body =~ "Order Received!"
    assert email.html_body =~ "Margherita Pizza"
    assert email.html_body =~ "Garlic Bread"
    assert email.html_body =~ "Large"
    assert email.html_body =~ "Extra Cheese"
    assert email.html_body =~ "Please leave at the door."
    assert email.html_body =~ "$25.00"
    assert email.html_body =~ "/orders/pizza-heaven/#{order.id}"
  end
end
