defmodule SupervisedSlices.BillingTest do
  use ExUnit.Case, async: true
  alias SupervisedSlices.Billing

  describe "parse_subscription_status/1" do
    test "correctly parses various Stripe statuses" do
      assert Billing.parse_subscription_status("active") == :active
      assert Billing.parse_subscription_status("trialing") == :trialing
      assert Billing.parse_subscription_status("past_due") == :past_due
      assert Billing.parse_subscription_status("canceled") == :canceled
      assert Billing.parse_subscription_status("unpaid") == :unpaid
      assert Billing.parse_subscription_status("incomplete") == :incomplete
      assert Billing.parse_subscription_status("incomplete_expired") == :incomplete_expired
    end

    test "returns :none for unknown statuses" do
      assert Billing.parse_subscription_status("unknown") == :none
      assert Billing.parse_subscription_status("something_else") == :none
    end
  end
end
