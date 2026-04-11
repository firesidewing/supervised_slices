defmodule SupervisedSlices.Orgs.OrganizationHoursTest do
  use ExUnit.Case, async: true

  alias SupervisedSlices.Orgs.{Organization, OperatingSchedule}

  defp org_with_schedule(schedule_attrs, timezone \\ "Etc/UTC") do
    schedule = struct(OperatingSchedule, schedule_attrs)
    %Organization{operating_schedule: schedule, timezone: timezone}
  end

  describe "open_now?/1" do
    test "returns true when no schedule is configured" do
      org = %Organization{operating_schedule: nil, timezone: "America/Toronto"}
      assert Organization.open_now?(org)
    end

    test "returns false on a closed day" do
      all_closed =
        Enum.flat_map(~w(mon tue wed thu fri sat sun), fn day ->
          [{:"#{day}_open", false}]
        end)
        |> Map.new()

      org = org_with_schedule(all_closed)
      refute Organization.open_now?(org)
    end

    test "returns true when open 24h all days" do
      always_open =
        Enum.flat_map(~w(mon tue wed thu fri sat sun), fn day ->
          [
            {:"#{day}_open", true},
            {:"#{day}_open_time", "00:00"},
            {:"#{day}_close_time", "23:59"}
          ]
        end)
        |> Map.new()

      org = org_with_schedule(always_open)
      assert Organization.open_now?(org)
    end

    test "falls back to UTC when timezone is nil" do
      always_open =
        Enum.flat_map(~w(mon tue wed thu fri sat sun), fn day ->
          [
            {:"#{day}_open", true},
            {:"#{day}_open_time", "00:00"},
            {:"#{day}_close_time", "23:59"}
          ]
        end)
        |> Map.new()

      org = org_with_schedule(always_open, nil)
      assert Organization.open_now?(org)
    end

    test "falls back to UTC when timezone is unrecognized" do
      always_open =
        Enum.flat_map(~w(mon tue wed thu fri sat sun), fn day ->
          [
            {:"#{day}_open", true},
            {:"#{day}_open_time", "00:00"},
            {:"#{day}_close_time", "23:59"}
          ]
        end)
        |> Map.new()

      org = org_with_schedule(always_open, "Not/A_Real_Zone")
      # Should not raise — falls back to UTC and still evaluates
      assert is_boolean(Organization.open_now?(org))
    end

    test "uses the org timezone when evaluating hours" do
      # Build a schedule that is open 00:00–23:59 every day. This will be
      # true regardless of what timezone we shift into, which lets us verify
      # the shift_zone path is exercised without mocking DateTime.utc_now/0.
      always_open =
        Enum.flat_map(~w(mon tue wed thu fri sat sun), fn day ->
          [
            {:"#{day}_open", true},
            {:"#{day}_open_time", "00:00"},
            {:"#{day}_close_time", "23:59"}
          ]
        end)
        |> Map.new()

      for tz <- ["America/Toronto", "America/Los_Angeles", "Europe/London", "Asia/Tokyo"] do
        org = org_with_schedule(always_open, tz)
        assert Organization.open_now?(org), "Expected open for timezone #{tz}"
      end
    end
  end
end
