defmodule SupervisedSlices.Orgs.OperatingSchedule do
  @moduledoc """
  Weekly operating schedule for an organization.

  Times are stored as "HH:MM" strings (24-hour) in UTC.
  Each day has an `is_open` boolean and optional `open_time` / `close_time`.
  When `close_time` < `open_time` the business closes after midnight on the next day.

  Days follow ISO weekday numbering: 1 = Monday … 7 = Sunday.
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    # Monday
    attribute :mon_open, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :mon_open_time, :string do
      default "11:00"
      public? true
    end

    attribute :mon_close_time, :string do
      default "22:00"
      public? true
    end

    # Tuesday
    attribute :tue_open, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :tue_open_time, :string do
      default "11:00"
      public? true
    end

    attribute :tue_close_time, :string do
      default "22:00"
      public? true
    end

    # Wednesday
    attribute :wed_open, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :wed_open_time, :string do
      default "11:00"
      public? true
    end

    attribute :wed_close_time, :string do
      default "22:00"
      public? true
    end

    # Thursday
    attribute :thu_open, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :thu_open_time, :string do
      default "11:00"
      public? true
    end

    attribute :thu_close_time, :string do
      default "22:00"
      public? true
    end

    # Friday
    attribute :fri_open, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :fri_open_time, :string do
      default "11:00"
      public? true
    end

    attribute :fri_close_time, :string do
      default "23:00"
      public? true
    end

    # Saturday
    attribute :sat_open, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :sat_open_time, :string do
      default "11:00"
      public? true
    end

    attribute :sat_close_time, :string do
      default "23:00"
      public? true
    end

    # Sunday
    attribute :sun_open, :boolean do
      default false
      allow_nil? false
      public? true
    end

    attribute :sun_open_time, :string do
      default "12:00"
      public? true
    end

    attribute :sun_close_time, :string do
      default "21:00"
      public? true
    end
  end
end
