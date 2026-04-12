defmodule SupervisedSlices.Billing do
  @moduledoc """
  Stripe billing helpers for org subscription management.
  """

  alias SupervisedSlices.Orgs.Organization

  @doc """
  Creates a Stripe customer for the given org and email, saves the customer ID
  to the org, and returns `{:ok, updated_org}`.
  """
  def create_customer_for_org(%Organization{stripe_customer_id: nil} = org, email) do
    case Stripe.Customer.create(%{email: email, name: org.name}) do
      {:ok, customer} ->
        updated =
          org
          |> Ash.Changeset.for_update(:update_billing, %{stripe_customer_id: customer.id})
          |> Ash.update!(authorize?: false)

        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_customer_for_org(%Organization{} = org, _email), do: {:ok, org}

  @doc """
  Creates a Stripe Checkout Session for a new subscription.
  Returns `{:ok, session}` where `session.url` is the hosted checkout URL.
  """
  def create_checkout_session(customer_id, success_url, cancel_url) do
    price_id = Application.get_env(:supervised_slices, :stripe)[:price_id]

    Stripe.Checkout.Session.create(%{
      customer: customer_id,
      mode: "subscription",
      line_items: [%{price: price_id, quantity: 1}],
      success_url: success_url <> "?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: cancel_url,
      payment_method_collection: "always"
    })
  end

  @doc """
  Creates a Stripe Customer Portal session so the customer can manage their
  subscription (update card, cancel, etc.) without developer involvement.
  Returns `{:ok, session}` where `session.url` is the portal URL.
  """
  def create_portal_session(customer_id, return_url) do
    Stripe.BillingPortal.Session.create(%{
      customer: customer_id,
      return_url: return_url
    })
  end

  @doc """
  Converts a Stripe subscription status string to the atom stored on the org.
  """
  def parse_subscription_status(status) when is_binary(status) do
    case status do
      "active" -> :active
      "trialing" -> :trialing
      "past_due" -> :past_due
      "canceled" -> :canceled
      "unpaid" -> :unpaid
      "incomplete" -> :incomplete
      "incomplete_expired" -> :incomplete_expired
      _ -> :none
    end
  end
end
