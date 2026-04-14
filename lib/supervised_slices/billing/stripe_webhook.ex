defmodule SupervisedSlices.Billing.StripeWebhook do
  @moduledoc """
  Structs representing Stripe webhook events we care about.
  """

  defmodule Subscription do
    @derive [Jason.Encoder]
    defstruct [:id, :customer, :status, :metadata]
  end

  defmodule CheckoutSession do
    @derive [Jason.Encoder]
    defstruct [:id, :customer, :status, :mode, :metadata, :subscription, :payment_status]
  end

  defmodule Event do
    @derive [Jason.Encoder]
    defstruct [:id, :type, :subscription, :checkout_session]
  end

  def parse!(raw_body) when is_binary(raw_body) do
    data = Jason.decode!(raw_body)
    object = data["data"]["object"]
    type = data["type"]

    %Event{
      id: data["id"],
      type: type,
      subscription:
        if(String.starts_with?(type, "customer.subscription."), do: parse_subscription(object)),
      checkout_session:
        if(type == "checkout.session.completed", do: parse_checkout_session(object))
    }
  end

  defp parse_subscription(%{"id" => id, "customer" => customer, "status" => status} = obj) do
    %Subscription{
      id: id,
      customer: customer,
      status: status,
      metadata: Map.get(obj, "metadata", %{})
    }
  end

  defp parse_subscription(_), do: nil

  defp parse_checkout_session(%{"id" => id, "customer" => customer, "status" => status} = obj) do
    %CheckoutSession{
      id: id,
      customer: customer,
      status: status,
      mode: Map.get(obj, "mode"),
      metadata: Map.get(obj, "metadata", %{}),
      subscription: Map.get(obj, "subscription"),
      payment_status: Map.get(obj, "payment_status")
    }
  end

  defp parse_checkout_session(_), do: nil
end
