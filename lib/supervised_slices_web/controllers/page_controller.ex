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
      preview_editor_items: [
        %{
          name: "Margherita",
          description: "San Marzano tomato, buffalo mozzarella, fresh basil, olive oil.",
          price_display: "$14",
          image_url:
            "https://images.unsplash.com/photo-1513104890138-7c749659a591?q=80&w=600&auto=format&fit=crop",
          available: true,
          sizes_count: 3,
          mods_count: 1
        },
        %{
          name: "Pepperoni",
          description: "Double pepperoni, provolone, spicy honey glaze.",
          price_display: "$16",
          image_url:
            "https://images.unsplash.com/photo-1628840042765-356cda07504e?q=80&w=600&auto=format&fit=crop",
          available: true,
          sizes_count: 3,
          mods_count: 2
        },
        %{
          name: "Truffle Bianca",
          description: "Truffle oil, fontina, wild mushrooms, fresh arugula.",
          price_display: "$19",
          image_url:
            "https://images.unsplash.com/photo-1590947132387-155cc02f3212?q=80&w=600&auto=format&fit=crop",
          available: false,
          sizes_count: 2,
          mods_count: 0
        }
      ],
      preview_menu_items: [
        %{
          name: "Margherita",
          description: "San Marzano tomato, buffalo mozzarella, fresh basil",
          price_display: "$14",
          image_url:
            "https://images.unsplash.com/photo-1541745537411-b8046dc6d66c?q=80&w=400&auto=format&fit=crop"
        },
        %{
          name: "Pepperoni",
          description: "Double pepperoni, provolone, spicy honey glaze",
          price_display: "$16",
          image_url:
            "https://images.unsplash.com/photo-1628840042765-356cda07504e?q=80&w=400&auto=format&fit=crop"
        },
        %{
          name: "Truffle Bianca",
          description: "Truffle oil, fontina, wild mushrooms, arugula",
          price_display: "$19",
          image_url:
            "https://images.unsplash.com/photo-1513104890138-7c749659a591?q=80&w=400&auto=format&fit=crop"
        },
        %{
          name: "Diavola",
          description: "Spicy salami, nduja, chilli, fior di latte",
          price_display: "$17",
          image_url:
            "https://images.unsplash.com/photo-1534308983496-4fabb1a015ee?q=80&w=400&auto=format&fit=crop"
        }
      ],
      preview_counter_item: %{
        name: "Margherita",
        description: "San Marzano tomato, buffalo mozzarella, fresh basil, olive oil.",
        image_url:
          "https://images.unsplash.com/photo-1541745537411-b8046dc6d66c?q=80&w=600&auto=format&fit=crop",
        total_display: "$14",
        sizes: [
          %{selected: false, name: "Small", label: "10\"", price_display: "$12"},
          %{selected: true, name: "Medium", label: "12\"", price_display: "$14"},
          %{selected: false, name: "Large", label: "14\"", price_display: "$17"}
        ],
        modifier_groups: [
          %{
            name: "Extras",
            required: false,
            max_selections: nil,
            modifiers: [
              %{selected: false, icon: "spa", name: "Extra Basil"},
              %{selected: true, icon: "egg", name: "Buffalo Mozz."},
              %{selected: false, icon: "water_drop", name: "Chilli Oil"}
            ]
          }
        ]
      }
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
