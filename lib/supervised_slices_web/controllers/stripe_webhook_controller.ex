defmodule SupervisedSlicesWeb.StripeWebhookController do
  use SupervisedSlicesWeb, :controller
  require Logger

  alias SupervisedSlices.Billing
  alias SupervisedSlices.Orgs.Organization

  @handled_events ~w(
    customer.subscription.created
    customer.subscription.updated
    customer.subscription.deleted
  )

  def event(conn, _params) do
    raw_body = conn.private |> Map.get(:raw_body, []) |> Enum.reverse() |> IO.iodata_to_binary()
    sig = conn |> get_req_header("stripe-signature") |> List.first()
    secret = Application.get_env(:supervised_slices, :stripe)[:webhook_secret]

    case Stripe.Webhook.construct_event(raw_body, sig, secret) do
      {:ok, %{type: type} = event} when type in @handled_events ->
        case handle_subscription_event(event) do
          :ok ->
            send_resp(conn, 200, "ok")

          {:error, reason} ->
            Logger.error("Stripe webhook processing error: #{inspect(reason)}")

            conn
            |> put_status(500)
            |> json(%{error: "Internal Server Error"})
        end

      {:ok, _event} ->
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{error: reason})
    end
  end

  defp handle_subscription_event(%{data: %{object: subscription}}) do
    customer_id = subscription.customer
    subscription_id = subscription.id
    status = Billing.parse_subscription_status(subscription.status)

    case Organization.by_stripe_customer(customer_id, authorize?: false) do
      {:ok, nil} ->
        :ok

      {:ok, org} ->
        org
        |> Ash.Changeset.for_update(:update_billing, %{
          stripe_subscription_id: subscription_id,
          subscription_status: status
        })
        |> Ash.update(authorize?: false)
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
