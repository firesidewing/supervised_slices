defmodule SupervisedSlices.Billing.StripeWebhook do
  @moduledoc """
  Structs representing Stripe webhook events we care about.
  """

  defmodule Subscription do
    @derive [Jason.Encoder]
    defstruct [:id, :customer, :status]
  end

  defmodule Event do
    @derive [Jason.Encoder]
    defstruct [:id, :type, :subscription]
  end

  def parse!(raw_body) when is_binary(raw_body) do
    data = Jason.decode!(raw_body)

    %Event{
      id: data["id"],
      type: data["type"],
      subscription: parse_subscription(data["data"]["object"])
    }
  end

  defp parse_subscription(%{"id" => id, "customer" => customer, "status" => status}) do
    %Subscription{
      id: id,
      customer: customer,
      status: status
    }
  end

  defp parse_subscription(_), do: nil
end
