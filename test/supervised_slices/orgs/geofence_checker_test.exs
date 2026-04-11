defmodule SupervisedSlices.Orgs.GeofenceCheckerTest do
  use ExUnit.Case, async: true

  alias SupervisedSlices.Orgs.GeofenceChecker

  # GeofenceChecker only does structural field access (%{center_lat: ...} etc.),
  # so plain maps are sufficient for the fence — no need to build Ash structs.
  defp org_with_fence(attrs) do
    fence = Map.merge(%{center_lat: nil, center_lng: nil, radius_in_km: nil}, attrs)
    %{delivery_geo_fence: fence}
  end

  defp org_no_fence, do: %{delivery_geo_fence: nil}

  # Downtown Toronto — used as geofence center in distance tests.
  @toronto_lat 43.6532
  @toronto_lng -79.3832

  # Nominatim-shaped JSON response body helpers.
  defp nominatim_hit(lat, lng),
    do: [%{"lat" => "#{lat}", "lon" => "#{lng}", "display_name" => "Test"}]

  defp nominatim_empty, do: []

  defp stub_nominatim(body) do
    Req.Test.stub(:nominatim, fn conn ->
      Req.Test.json(conn, body)
    end)
  end

  # ---------------------------------------------------------------------------
  # Cases that never touch geocoding
  # ---------------------------------------------------------------------------

  describe "within_zone?/2 — no geocoding needed" do
    test "returns true when org has no geofence configured" do
      assert GeofenceChecker.within_zone?(org_no_fence(), %{"street" => "1 Main St"})
    end

    test "returns true when fence center_lat is nil" do
      org = org_with_fence(%{center_lat: nil, center_lng: @toronto_lng, radius_in_km: 10})
      assert GeofenceChecker.within_zone?(org, %{"street" => "1 Main St"})
    end

    test "returns true when fence center_lng is nil" do
      org = org_with_fence(%{center_lat: @toronto_lat, center_lng: nil, radius_in_km: 10})
      assert GeofenceChecker.within_zone?(org, %{"street" => "1 Main St"})
    end

    test "returns true when fence radius is nil" do
      org = org_with_fence(%{center_lat: @toronto_lat, center_lng: @toronto_lng, radius_in_km: nil})
      assert GeofenceChecker.within_zone?(org, %{"street" => "1 Main St"})
    end

    test "returns true when fence radius is zero" do
      org = org_with_fence(%{center_lat: @toronto_lat, center_lng: @toronto_lng, radius_in_km: 0})
      assert GeofenceChecker.within_zone?(org, %{"street" => "1 Main St"})
    end

    test "returns true for a plain map org with no delivery_geo_fence key" do
      assert GeofenceChecker.within_zone?(%{}, %{"street" => "1 Main St"})
    end
  end

  # ---------------------------------------------------------------------------
  # Fail-open: geocoding failures allow the order through
  # ---------------------------------------------------------------------------

  describe "within_zone?/2 — geocoding fails → fail open" do
    test "returns true when Nominatim returns an empty result list" do
      stub_nominatim(nominatim_empty())
      org = org_with_fence(%{center_lat: @toronto_lat, center_lng: @toronto_lng, radius_in_km: 5})
      assert GeofenceChecker.within_zone?(org, %{"street" => "1 Main St", "city" => "Toronto", "zip" => "M5V"})
    end

    test "returns true when Nominatim returns a non-200 status" do
      Req.Test.stub(:nominatim, fn conn ->
        Plug.Conn.send_resp(conn, 503, "Service Unavailable")
      end)

      org = org_with_fence(%{center_lat: @toronto_lat, center_lng: @toronto_lng, radius_in_km: 5})
      assert GeofenceChecker.within_zone?(org, %{"street" => "1 Main St"})
    end
  end

  # ---------------------------------------------------------------------------
  # Distance checks with mocked geocoding
  # ---------------------------------------------------------------------------

  describe "within_zone?/2 — address inside zone" do
    test "returns true when geocoded point is well within the radius" do
      # Point 1 km north of Toronto centre — well inside a 10 km fence.
      nearby_lat = @toronto_lat + 0.009  # ~1 km north
      stub_nominatim(nominatim_hit(nearby_lat, @toronto_lng))

      org = org_with_fence(%{center_lat: @toronto_lat, center_lng: @toronto_lng, radius_in_km: 10})
      assert GeofenceChecker.within_zone?(org, %{"street" => "1 Main St", "city" => "Toronto", "zip" => "M5V"})
    end

    test "returns true when geocoded point is exactly at the center" do
      stub_nominatim(nominatim_hit(@toronto_lat, @toronto_lng))

      org = org_with_fence(%{center_lat: @toronto_lat, center_lng: @toronto_lng, radius_in_km: 5})
      assert GeofenceChecker.within_zone?(org, %{"street" => "1 Main St"})
    end
  end

  describe "within_zone?/2 — address outside zone" do
    test "returns false when geocoded point is clearly beyond the radius" do
      # Mississauga, roughly 25 km west of Toronto downtown.
      mississauga_lat = 43.5890
      mississauga_lng = -79.6441
      stub_nominatim(nominatim_hit(mississauga_lat, mississauga_lng))

      org = org_with_fence(%{center_lat: @toronto_lat, center_lng: @toronto_lng, radius_in_km: 10})
      refute GeofenceChecker.within_zone?(org, %{"street" => "100 City Centre Dr", "city" => "Mississauga", "zip" => "L5B"})
    end

    test "returns false when geocoded point is just beyond a tight radius" do
      # Point ~3 km north — outside a 2 km fence.
      far_lat = @toronto_lat + 0.027  # ~3 km north
      stub_nominatim(nominatim_hit(far_lat, @toronto_lng))

      org = org_with_fence(%{center_lat: @toronto_lat, center_lng: @toronto_lng, radius_in_km: 2})
      refute GeofenceChecker.within_zone?(org, %{"street" => "Far Away St"})
    end
  end

  # ---------------------------------------------------------------------------
  # Address key formats
  # ---------------------------------------------------------------------------

  describe "within_zone?/2 — address key formats" do
    test "accepts atom-key address maps" do
      stub_nominatim(nominatim_hit(@toronto_lat, @toronto_lng))

      org = org_with_fence(%{center_lat: @toronto_lat, center_lng: @toronto_lng, radius_in_km: 5})
      assert GeofenceChecker.within_zone?(org, %{street: "1 Main St", city: "Toronto", zip: "M5V"})
    end
  end
end
