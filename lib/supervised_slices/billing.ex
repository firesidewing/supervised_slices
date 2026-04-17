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
    case Stripe.Customer.create(%{email: to_string(email), name: to_string(org.name)}) do
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
  def create_checkout_session(customer_id, price_id, plan_name, success_url, cancel_url) do
    Stripe.Checkout.Session.create(%{
      customer: customer_id,
      mode: "subscription",
      line_items: [%{price: price_id, quantity: 1}],
      subscription_data: %{
        metadata: %{plan: to_string(plan_name)}
      },
      metadata: %{plan: to_string(plan_name)},
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
  Creates a Stripe Checkout Session for a one-time purchase.
  Returns `{:ok, session}` where `session.url` is the hosted checkout URL.
  """
  def create_one_time_checkout_session(customer_id, price_id, metadata, success_url, cancel_url) do
    Stripe.Checkout.Session.create(%{
      customer: customer_id,
      mode: "payment",
      line_items: [%{price: price_id, quantity: 1}],
      metadata: metadata,
      success_url: success_url <> "?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: cancel_url
    })
  end

  @doc """
  Retrieves a Stripe Checkout Session and, if it is complete, immediately
  updates the org's subscription or purchase fields so access is granted
  without waiting for the webhook. Safe to call multiple times (idempotent).
  """
  def fulfill_from_checkout_session(%Organization{} = org, session_id)
      when is_binary(session_id) do
    with {:ok, session} <- Stripe.Checkout.Session.retrieve(session_id),
         true <- session.status == "complete" do
      params =
        cond do
          # Subscription mode
          session.mode == "subscription" and is_binary(session.subscription) ->
            status = if session.payment_status == "paid", do: :active, else: :incomplete
            plan = session.metadata["plan"]

            p = %{
              stripe_subscription_id: session.subscription,
              subscription_status: status
            }

            if plan in ["basic", "pro"] do
              Map.put(p, :plan, String.to_existing_atom(plan))
            else
              p
            end

          # Payment mode (one-time)
          session.mode == "payment" and session.metadata["menu_upload"] == "true" ->
            if session.payment_status == "paid" do
              %{menu_upload_purchased: true}
            else
              %{}
            end

          true ->
            %{}
        end

      if params != %{} do
        org
        |> Ash.Changeset.for_update(:update_billing, params)
        |> Ash.update(authorize?: false)
      else
        {:ok, org}
      end
    else
      _ -> {:ok, org}
    end
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
