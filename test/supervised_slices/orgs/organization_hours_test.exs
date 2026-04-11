defmodule SupervisedSlices.Orgs.OrganizationHoursTest do
  use ExUnit.Case, async: true

  alias SupervisedSlices.Orgs.{Organization, OperatingSchedule}

  defp org_with_schedule(schedule_attrs) do
    schedule = struct(OperatingSchedule, schedule_attrs)
    %Organization{operating_schedule: schedule}
  end

  describe "open_now?/1" do
    test "returns true when no schedule is configured" do
      org = %Organization{operating_schedule: nil}
      assert Organization.open_now?(org)
    end

    test "returns false on a closed day" do
      # Build an org closed all week
      all_closed =
        Enum.flat_map(~w(mon tue wed thu fri sat sun), fn day ->
          [{:"#{day}_open", false}]
        end)
        |> Map.new()

      org = org_with_schedule(all_closed)
      refute Organization.open_now?(org)
    end

    test "returns true when current time is within open hours" do
      # We can't control the current time in this test, so instead we verify
      # the open_now?/1 logic by calling it on an org that is open 24h on all days.
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
  end
end
