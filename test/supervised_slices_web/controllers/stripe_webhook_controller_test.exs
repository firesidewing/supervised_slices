defmodule SupervisedSlicesWeb.StripeWebhookControllerTest do
  use SupervisedSlicesWeb.ConnCase, async: true
  alias SupervisedSlices.Orgs.Organization

  @secret "whsec_test_secret"

  setup do
    Application.put_env(:supervised_slices, :stripe, webhook_secret: @secret)
    :ok
  end

  defp generate_signature(payload, secret) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    signed_payload = "#{timestamp}.#{payload}"
    hmac = :crypto.mac(:hmac, :sha256, secret, signed_payload) |> Base.encode16(case: :lower)
    "t=#{timestamp},v1=#{hmac}"
  end

  describe "POST /webhooks/stripe" do
    test "successfully updates organization on customer.subscription.updated", %{conn: conn} do
      _org =
        Organization
        |> Ash.Changeset.for_create(:create, %{name: "Test Org"})
        |> Ash.create!(authorize?: false)
        |> Ash.Changeset.for_update(:update_billing, %{stripe_customer_id: "cus_123"})
        |> Ash.update!(authorize?: false)

      payload =
        %{
          id: "evt_123",
          type: "customer.subscription.updated",
          data: %{
            object: %{
              id: "sub_456",
              customer: "cus_123",
              status: "active"
            }
          }
        }
        |> Jason.encode!()

      sig = generate_signature(payload, @secret)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", sig)
        |> post("/webhooks/stripe", payload)

      assert response(conn, 200) == "ok"

      org = Organization.by_stripe_customer!("cus_123", authorize?: false)
      assert org.stripe_subscription_id == "sub_456"
      assert org.subscription_status == :active
    end

    test "successfully updates organization on customer.subscription.created", %{conn: conn} do
      _org =
        Organization
        |> Ash.Changeset.for_create(:create, %{name: "Test Org"})
        |> Ash.create!(authorize?: false)
        |> Ash.Changeset.for_update(:update_billing, %{stripe_customer_id: "cus_123"})
        |> Ash.update!(authorize?: false)

      payload =
        %{
          id: "evt_123",
          type: "customer.subscription.created",
          data: %{
            object: %{
              id: "sub_456",
              customer: "cus_123",
              status: "trialing"
            }
          }
        }
        |> Jason.encode!()

      sig = generate_signature(payload, @secret)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", sig)
        |> post("/webhooks/stripe", payload)

      assert response(conn, 200) == "ok"

      org = Organization.by_stripe_customer!("cus_123", authorize?: false)
      assert org.stripe_subscription_id == "sub_456"
      assert org.subscription_status == :trialing
    end

    test "successfully updates organization on customer.subscription.deleted", %{conn: conn} do
      _org =
        Organization
        |> Ash.Changeset.for_create(:create, %{name: "Test Org"})
        |> Ash.create!(authorize?: false)
        |> Ash.Changeset.for_update(:update_billing, %{
          stripe_customer_id: "cus_123",
          stripe_subscription_id: "sub_456",
          subscription_status: :active
        })
        |> Ash.update!(authorize?: false)

      payload =
        %{
          id: "evt_123",
          type: "customer.subscription.deleted",
          data: %{
            object: %{
              id: "sub_456",
              customer: "cus_123",
              status: "canceled"
            }
          }
        }
        |> Jason.encode!()

      sig = generate_signature(payload, @secret)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", sig)
        |> post("/webhooks/stripe", payload)

      assert response(conn, 200) == "ok"

      org = Organization.by_stripe_customer!("cus_123", authorize?: false)
      assert org.subscription_status == :canceled
    end

    test "returns 400 for invalid signature", %{conn: conn} do
      payload = %{type: "customer.subscription.updated"} |> Jason.encode!()
      sig = "invalid_sig"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", sig)
        |> post("/webhooks/stripe", payload)

      assert response(conn, 400) =~ "error"
    end

    test "returns 200 ok for unhandled events", %{conn: conn} do
      payload =
        %{
          id: "evt_unknown",
          type: "invoice.created",
          data: %{object: %{}}
        }
        |> Jason.encode!()

      sig = generate_signature(payload, @secret)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", sig)
        |> post("/webhooks/stripe", payload)

      assert response(conn, 200) == "ok"
    end

    test "successfully updates organization on checkout.session.completed for menu upload", %{
      conn: conn
    } do
      org =
        Organization
        |> Ash.Changeset.for_create(:create, %{name: "Test Org"})
        |> Ash.create!(authorize?: false)
        |> Ash.Changeset.for_update(:update_billing, %{stripe_customer_id: "cus_123"})
        |> Ash.update!(authorize?: false)

      assert org.menu_upload_purchased == false

      payload =
        %{
          id: "evt_123",
          type: "checkout.session.completed",
          data: %{
            object: %{
              id: "cs_123",
              customer: "cus_123",
              status: "complete",
              mode: "payment",
              payment_status: "paid",
              metadata: %{
                menu_upload: "true",
                org_id: org.id
              },
              subscription: nil
            }
          }
        }
        |> Jason.encode!()

      sig = generate_signature(payload, @secret)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", sig)
        |> post("/webhooks/stripe", payload)

      assert response(conn, 200) == "ok"

      org = Organization.by_stripe_customer!("cus_123", authorize?: false)
      assert org.menu_upload_purchased == true
    end

    test "successfully updates organization on checkout.session.completed for subscription", %{
      conn: conn
    } do
      _org =
        Organization
        |> Ash.Changeset.for_create(:create, %{name: "Test Org"})
        |> Ash.create!(authorize?: false)
        |> Ash.Changeset.for_update(:update_billing, %{stripe_customer_id: "cus_123"})
        |> Ash.update!(authorize?: false)

      payload =
        %{
          id: "evt_123",
          type: "checkout.session.completed",
          data: %{
            object: %{
              id: "cs_123",
              customer: "cus_123",
              status: "complete",
              mode: "subscription",
              payment_status: "paid",
              metadata: %{
                plan: "pro"
              },
              subscription: "sub_pro_123"
            }
          }
        }
        |> Jason.encode!()

      sig = generate_signature(payload, @secret)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", sig)
        |> post("/webhooks/stripe", payload)

      assert response(conn, 200) == "ok"

      org = Organization.by_stripe_customer!("cus_123", authorize?: false)
      assert org.stripe_subscription_id == "sub_pro_123"
      assert org.plan == :pro
      assert org.subscription_status == :active
    end

    test "returns 200 ok if organization not found", %{conn: conn} do
      payload =
        %{
          id: "evt_123",
          type: "customer.subscription.updated",
          data: %{
            object: %{
              id: "sub_456",
              customer: "cus_nonexistent",
              status: "active"
            }
          }
        }
        |> Jason.encode!()

      sig = generate_signature(payload, @secret)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", sig)
        |> post("/webhooks/stripe", payload)

      assert response(conn, 200) == "ok"
    end
  end
end
