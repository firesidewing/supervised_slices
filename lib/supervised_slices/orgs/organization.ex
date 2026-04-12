defmodule SupervisedSlices.Orgs.Organization do
  use Ash.Resource,
    otp_app: :supervised_slices,
    domain: SupervisedSlices.Orgs,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  postgres do
    table "organizations"
    repo SupervisedSlices.Repo
  end

  oban do
    triggers do
      trigger :cleanup_stale_carts do
        scheduler_cron "0 * * * *"
        scheduler_queue :cart_cleanup
        queue :cart_cleanup
        action :cleanup_stale_carts
        where expr(active == true)
        worker_module_name SupervisedSlices.Orgs.Organization.AshOban.Worker.CleanupStaleCarts

        scheduler_module_name SupervisedSlices.Orgs.Organization.AshOban.Scheduler.CleanupStaleCarts
      end
    end
  end

  code_interface do
    define :update_settings, action: :update_settings
    define :update_branding, action: :update_branding
    define :update_billing, action: :update_billing
    define :by_stripe_customer, action: :by_stripe_customer, args: [:customer_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :slug]

      change fn changeset, _ ->
        if Ash.Changeset.get_attribute(changeset, :slug) do
          changeset
        else
          case Ash.Changeset.get_attribute(changeset, :name) do
            nil ->
              changeset

            name ->
              slug =
                name
                |> String.downcase()
                |> String.replace(~r/[^a-z0-9]/, "-")
                |> String.replace(~r/-+/, "-")
                |> String.trim("-")

              Ash.Changeset.force_change_attribute(changeset, :slug, slug)
          end
        end
      end
    end

    update :update do
      accept [:name, :active]
    end

    update :update_settings do
      accept [
        :tax_rate,
        :default_prep_time,
        :delivery_enabled,
        :pickup_enabled,
        :delivery_fee,
        :delivery_min_order,
        :timezone
      ]

      argument :delivery_geo_fence, :map
      argument :operating_schedule, :map

      change set_attribute(:delivery_geo_fence, arg(:delivery_geo_fence))
      change set_attribute(:operating_schedule, arg(:operating_schedule))
    end

    update :update_branding do
      accept [:logo_url, :primary_color, :secondary_color]
    end

    read :by_slug do
      argument :slug, :string, allow_nil?: false
      get? true
      filter expr(slug == ^arg(:slug))
    end

    update :update_billing do
      accept [:stripe_customer_id, :stripe_subscription_id, :subscription_status]
    end

    read :by_stripe_customer do
      argument :customer_id, :string, allow_nil?: false
      get? true
      filter expr(stripe_customer_id == ^arg(:customer_id))
    end

    update :cleanup_stale_carts do
      accept []
      require_atomic? false

      change fn changeset, _context ->
        require Ash.Query

        Ash.Changeset.after_action(changeset, fn _changeset, org ->
          SupervisedSlices.Cart.Cart
          |> Ash.Query.filter(status == :active and updated_at < ago(24, :hour))
          |> Ash.bulk_update!(:abandon, %{}, authorize?: false, tenant: org.id)

          {:ok, org}
        end)
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    bypass action(:update_settings) do
      authorize_if always()
    end

    bypass action(:update_branding) do
      authorize_if always()
    end

    bypass action(:update_billing) do
      authorize_if always()
    end

    bypass action(:cleanup_stale_carts) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:superadmin, true)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 2
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
    end

    attribute :active, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :tax_rate, :decimal do
      default Decimal.new("0")
      allow_nil? false
      public? true
    end

    attribute :default_prep_time, :integer do
      default 20
      allow_nil? false
      public? true
    end

    attribute :delivery_enabled, :boolean do
      default false
      allow_nil? false
      public? true
    end

    attribute :pickup_enabled, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :delivery_fee, AshMoney.Types.Money do
      public? true
    end

    attribute :delivery_min_order, AshMoney.Types.Money do
      public? true
    end

    attribute :delivery_geo_fence, SupervisedSlices.Orgs.GeoFence do
      public? true
    end

    attribute :operating_schedule, SupervisedSlices.Orgs.OperatingSchedule do
      public? true
    end

    attribute :timezone, :string do
      default "Etc/UTC"
      allow_nil? true
      public? true
    end

    attribute :logo_url, :string do
      allow_nil? true
      public? true
    end

    attribute :primary_color, :string do
      allow_nil? true
      public? true
      constraints match: ~r/^#[0-9a-fA-F]{6}$/
    end

    attribute :secondary_color, :string do
      allow_nil? true
      public? true
      constraints match: ~r/^#[0-9a-fA-F]{6}$/
    end

    attribute :stripe_customer_id, :string do
      allow_nil? true
      public? false
    end

    attribute :stripe_subscription_id, :string do
      allow_nil? true
      public? false
    end

    attribute :subscription_status, :atom do
      default :none
      constraints one_of: [
                    :none,
                    :active,
                    :trialing,
                    :past_due,
                    :canceled,
                    :unpaid,
                    :incomplete,
                    :incomplete_expired
                  ]
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :memberships, SupervisedSlices.Orgs.Membership
  end

  calculations do
    calculate :subscribed?, :boolean, expr(subscription_status in [:active, :trialing])
  end

  identities do
    identity :unique_slug, [:slug]
  end

  # ---------------------------------------------------------------------------
  # Business hours helpers
  # ---------------------------------------------------------------------------

  @doc """
  Returns true if the organization is currently open based on its operating
  schedule. If no schedule has been configured, returns true (always open).

  The current time is shifted into the org's configured timezone before
  comparing against the scheduled hours. Falls back to UTC if no timezone
  is set or if the stored timezone string is unrecognized.
  """
  def open_now?(%{operating_schedule: nil}), do: true

  def open_now?(%{operating_schedule: schedule, timezone: timezone}) do
    tz = timezone || "Etc/UTC"

    now_local =
      case DateTime.shift_zone(DateTime.utc_now(), tz) do
        {:ok, dt} -> dt
        # Invalid timezone — fall back to UTC rather than crashing
        {:error, _} -> DateTime.utc_now()
      end

    day = Date.day_of_week(DateTime.to_date(now_local))
    current_time = DateTime.to_time(now_local)

    {is_open_key, open_key, close_key} = day_schedule_keys(day)

    is_open = Map.get(schedule, is_open_key)
    open_str = Map.get(schedule, open_key)
    close_str = Map.get(schedule, close_key)

    is_open == true and time_in_range?(current_time, open_str, close_str)
  end

  # ISO weekday: 1=Monday … 7=Sunday
  defp day_schedule_keys(1), do: {:mon_open, :mon_open_time, :mon_close_time}
  defp day_schedule_keys(2), do: {:tue_open, :tue_open_time, :tue_close_time}
  defp day_schedule_keys(3), do: {:wed_open, :wed_open_time, :wed_close_time}
  defp day_schedule_keys(4), do: {:thu_open, :thu_open_time, :thu_close_time}
  defp day_schedule_keys(5), do: {:fri_open, :fri_open_time, :fri_close_time}
  defp day_schedule_keys(6), do: {:sat_open, :sat_open_time, :sat_close_time}
  defp day_schedule_keys(7), do: {:sun_open, :sun_open_time, :sun_close_time}

  defp time_in_range?(_current, nil, _), do: true
  defp time_in_range?(_current, _, nil), do: true

  defp time_in_range?(current, open_str, close_str) do
    with {:ok, open} <- parse_hhmm(open_str),
         {:ok, close} <- parse_hhmm(close_str) do
      if Time.compare(close, open) == :gt do
        # Normal range: open <= now <= close
        Time.compare(current, open) in [:gt, :eq] and Time.compare(current, close) in [:lt, :eq]
      else
        # Cross-midnight: now >= open OR now <= close
        Time.compare(current, open) in [:gt, :eq] or Time.compare(current, close) in [:lt, :eq]
      end
    else
      _ -> true
    end
  end

  defp parse_hhmm(str) do
    Time.from_iso8601("#{str}:00")
  end
end
