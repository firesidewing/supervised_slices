defmodule SupervisedSlicesWeb.StripeWebhookController do
  use SupervisedSlicesWeb, :controller
  require Logger

  alias SupervisedSlices.Billing
  alias SupervisedSlices.Billing.StripeWebhook
  alias SupervisedSlices.Orgs.Organization

  @handled_events ~w(
    customer.subscription.created
    customer.subscription.updated
    customer.subscription.deleted
  )

  def event(conn, _params) do
    # Try to get cached body first from our custom key
    raw_body_list = Map.get(conn.private, :stripe_raw_body)

    {raw_body, chunks, source} =
      case raw_body_list do
        nil ->
          # Fallback: maybe it wasn't cached because of a path mismatch?
          case Plug.Conn.read_body(conn) do
            {:ok, body, _conn} -> {body, 1, "direct_read"}
            _ -> {"", 0, "none"}
          end

        list when is_list(list) ->
          {list |> Enum.reverse() |> IO.iodata_to_binary(), length(list), "cached"}
      end

    sig = conn |> get_req_header("stripe-signature") |> List.first()
    secret = Application.get_env(:supervised_slices, :stripe)[:webhook_secret]

    Logger.info(
      "Stripe Webhook Diagnosis: request_path=#{conn.request_path}, source=#{source}, chunks=#{chunks}, body_len=#{byte_size(raw_body)}, sig?=#{not is_nil(sig)}, secret_prefix=#{if is_binary(secret), do: String.slice(secret, 0, 8), else: "nil"}"
    )

    if raw_body == "" do
      Logger.error("Stripe webhook: raw_body is empty. path_info: #{inspect(conn.path_info)}")
    end

    if is_nil(sig) do
      Logger.error("Stripe webhook: stripe-signature header is missing")
    end

    if is_nil(secret) or secret == "whsec_placeholder" do
      Logger.error("Stripe webhook: secret is nil or default placeholder (value: #{inspect(secret)})")
    end

    case Stripe.Webhook.construct_event(raw_body, sig, secret) do
      {:ok, %{type: type}} when type in @handled_events ->
        Logger.info("Stripe webhook: received handled event #{type}")
        # Now parse it into our own structs for clarity
        event = StripeWebhook.parse!(raw_body)

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
        Logger.error("Stripe webhook: signature verification failed: #{inspect(reason)}")

        conn
        |> put_status(400)
        |> json(%{error: reason})
    end
  end

  defp handle_subscription_event(%StripeWebhook.Event{subscription: subscription}) do
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
