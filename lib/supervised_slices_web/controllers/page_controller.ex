defmodule SupervisedSlicesWeb.PageController do
  use SupervisedSlicesWeb, :controller

  def home(conn, _params) do
    user = conn.assigns[:current_user]
    now = DateTime.utc_now()

    render(conn, :home,
      kitchen_org: get_kitchen_org(user),
      preview_orders: [
        %{
          id: "00000000-0000-0000-0000-000000000042",
          status: :pending,
          customer_name: "Marco R.",
          inserted_at: DateTime.add(now, -90, :second),
          order_items: [
            %{
              quantity: 1,
              item_name: "Margherita",
              size_snapshot: %{"name" => "Large"},
              modifiers_snapshot: [%{"name" => "Extra Basil"}, %{"name" => "Buffalo Mozz."}]
            }
          ],
          notes: nil
        },
        %{
          id: "00000000-0000-0000-0000-000000000041",
          status: :preparing,
          customer_name: "Sofia K.",
          inserted_at: DateTime.add(now, -480, :second),
          order_items: [
            %{
              quantity: 1,
              item_name: "Pepperoni",
              size_snapshot: %{"name" => "Medium"},
              modifiers_snapshot: [%{"name" => "Double Pep"}, %{"name" => "Provolone"}]
            }
          ],
          notes: nil
        }
      ],
      preview_menu_item: %{
        name: "Margherita",
        description: "San Marzano tomato, buffalo mozzarella, fresh basil, olive oil.",
        total_display: "$16.00",
        sizes: [
          %{name: "10\"", label: "Personal", price_display: "$12", selected: false},
          %{name: "14\"", label: "Large", price_display: "$16", selected: true},
          %{name: "18\"", label: "Atelier", price_display: "$22", selected: false}
        ],
        modifier_groups: [
          %{
            name: "Toppings",
            required: false,
            max_selections: nil,
            modifiers: [
              %{name: "Extra Basil", icon: "spa", selected: true},
              %{name: "Buffalo Mozzarella", icon: "egg", selected: true},
              %{name: "Prosciutto di Parma", icon: "flatware", selected: false}
            ]
          }
        ]
      },
      preview_menu_items: [
        %{name: "Margherita", description: "San Marzano tomato, buffalo mozzarella, fresh basil", price_display: "$14"},
        %{name: "Pepperoni", description: "Double pepperoni, provolone, spicy honey glaze", price_display: "$16"},
        %{name: "Truffle Bianca", description: "Truffle oil, fontina, wild mushrooms, arugula", price_display: "$19"},
        %{name: "Diavola", description: "Spicy salami, nduja, chilli, fior di latte", price_display: "$17"}
      ]
    )
  end

  defp get_kitchen_org(nil), do: nil

  defp get_kitchen_org(user) do
    user.id
    |> SupervisedSlices.Orgs.Membership.get_kitchen_membership(authorize?: false)
    |> case do
      {:ok, [membership | _]} -> membership.organization
      _ -> nil
    end
  end
end
