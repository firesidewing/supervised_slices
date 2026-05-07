defmodule SupervisedSlices.Orders.Emails do
  use SupervisedSlicesWeb, :verified_routes
  import Swoosh.Email
  alias SupervisedSlices.Mailer

  def send_order_confirmation(order) do
    # Ensure order items and organization are loaded
    order = Ash.load!(order, [:order_items, :organization], authorize?: false)

    new()
    |> from({"Chitline", "orders@chitline.com"})
    |> to(to_string(order.customer_email))
    |> subject("Order Confirmation ##{order_number(order)} - #{order.organization.name}")
    |> html_body(order_confirmation_html(order))
    |> Mailer.deliver()
  end

  defp order_number(order) do
    order.id |> String.slice(-4, 4) |> String.upcase()
  end

  defp order_confirmation_html(order) do
    tracking_url = url(~p"/orders/#{order.organization.slug}/#{order.id}")

    primary = "#b90027"
    surface = "#faf9f6"
    surface_container_low = "#f4f3f1"
    on_surface_variant = "#5d3f3e"

    """
    <!DOCTYPE html>
    <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
        <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:ital,wght@0,400;0,700;0,800;1,800&family=Be+Vietnam+Pro:wght@400;500;700&display=swap" rel="stylesheet">
      </head>
      <body style="font-family: 'Plus Jakarta Sans', 'Be Vietnam Pro', Helvetica, Arial, sans-serif; background-color: #{surface}; margin: 0; padding: 40px 20px;">
        <div style="max-width: 600px; margin: 0 auto; background-color: #ffffff; border-radius: 48px; overflow: hidden; box-shadow: 0 12px 32px rgba(93, 63, 62, 0.08);">
          <!-- Header -->
          <table width="100%" cellpadding="0" cellspacing="0" style="padding: 32px 40px; border-bottom: 1px solid #{surface_container_low};">
            <tr>
              <td>
                <h1 style="color: #{primary}; margin: 0; font-size: 20px; font-weight: 900; letter-spacing: -0.02em; font-style: italic; text-transform: uppercase;">#{order.organization.name}</h1>
              </td>
              <td align="right">
                <span style="background-color: #{surface_container_low}; color: #{on_surface_variant}; padding: 6px 16px; border-radius: 999px; font-weight: 800; font-size: 12px; letter-spacing: 0.1em;">##{order_number(order)}</span>
              </td>
            </tr>
          </table>

          <!-- Status Hero -->
          <div style="padding: 48px 40px; text-align: center; background-color: #{primary}; color: #ffffff;">
            <div style="margin-bottom: 16px; font-size: 48px;">🍕</div>
            <h2 style="margin: 0 0 8px 0; font-size: 32px; font-weight: 900; letter-spacing: -0.03em; text-transform: uppercase; font-style: italic;">Order Received!</h2>
            <p style="margin: 0; font-size: 16px; opacity: 0.9; font-weight: 500;">We've received your order and the kitchen is getting started.</p>
          </div>

          <!-- CTA -->
          <div style="padding: 40px; text-align: center; background-color: #ffffff;">
            <a href="#{tracking_url}" style="display: inline-block; background-color: #{primary}; background: linear-gradient(to right, #{primary}, #e31837); color: #ffffff; padding: 18px 36px; border-radius: 16px; text-decoration: none; font-weight: 900; font-size: 16px; text-transform: uppercase; letter-spacing: 0.05em; box-shadow: 0 16px 32px rgba(185, 0, 39, 0.3);">Track Your Order Live</a>
            <p style="margin-top: 24px; font-size: 12px; color: #{on_surface_variant}; opacity: 0.6; text-transform: uppercase; font-weight: 800; letter-spacing: 0.1em;">Follow every step from oven to box</p>
          </div>

          <!-- Order Summary -->
          <div style="padding: 0 40px 48px 40px;">
            <div style="background-color: #{surface}; border-radius: 32px; padding: 32px;">
              <h3 style="font-size: 12px; text-transform: uppercase; color: #{on_surface_variant}; margin: 0 0 24px 0; letter-spacing: 0.15em; font-weight: 800; opacity: 0.6;">Your Selection</h3>

              <div style="margin-bottom: 24px;">
                #{render_items(order.order_items)}
              </div>

              <table width="100%" cellpadding="0" cellspacing="0" style="border-top: 2px solid #{surface_container_low}; padding-top: 24px;">
                <tr>
                  <td>
                    <span style="font-size: 18px; font-weight: 900; text-transform: uppercase; letter-spacing: -0.01em;">Total</span>
                  </td>
                  <td align="right">
                    <span style="font-size: 28px; font-weight: 900; color: #{primary}; letter-spacing: -0.02em;">#{Money.to_string!(order.total_price)}</span>
                  </td>
                </tr>
              </table>

              #{if order.notes && order.notes != "", do: "<div style='margin-top: 24px; padding: 20px; background-color: #ffffff; border-radius: 16px; font-style: italic; font-size: 13px; color: #{on_surface_variant}; line-height: 1.6;'><strong>Notes:</strong> \"#{order.notes}\"</div>", else: ""}
            </div>
          </div>

          <!-- Footer -->
          <div style="padding: 0 40px 40px 40px; text-align: center;">
            <p style="font-size: 12px; color: #{on_surface_variant}; opacity: 0.4; line-height: 1.6;">
              This is an automated confirmation for your order at #{order.organization.name}.<br/>
              If you have any questions, please contact the kitchen directly.
            </p>
          </div>
        </div>
      </body>
    </html>
    """
  end

  defp render_items(items) do
    primary = "#b90027"

    items
    |> Enum.map(fn item ->
      """
      <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom: 20px;">
        <tr>
          <td valign="top">
            <div style="display: inline-block; margin-bottom: 4px;">
              <span style="font-weight: 900; color: #{primary}; font-size: 14px; margin-right: 8px;">#{item.quantity}×</span>
              #{if item.size_snapshot, do: "<span style='text-transform: uppercase; font-weight: 800; font-size: 10px; color: #3a6843; background-color: #eaf0eb; padding: 2px 8px; border-radius: 6px; margin-right: 8px; letter-spacing: 0.05em;'>#{item.size_snapshot["name"]}</span>", else: ""}
              <span style="font-weight: 800; font-size: 15px; letter-spacing: -0.01em;">#{item.item_name}</span>
            </div>
            #{render_modifiers(item.modifiers_snapshot)}
          </td>
          <td valign="top" align="right" style="font-weight: 800; font-size: 14px; white-space: nowrap; padding-left: 16px;">
            #{Money.to_string!(Money.mult!(item.price_at_time, item.quantity))}
          </td>
        </tr>
      </table>
      """
    end)
    |> Enum.join("")
  end

  defp render_modifiers(modifiers) do
    on_surface_variant = "#5d3f3e"

    if modifiers && modifiers != [] do
      "<div style='margin-left: 28px; font-size: 11px; color: #{on_surface_variant}; opacity: 0.6; font-style: italic; font-weight: 500;'>" <>
        (Enum.map(modifiers, fn mod -> "+ #{mod["name"]}" end) |> Enum.join(", ")) <>
        "</div>"
    else
      ""
    end
  end
end
