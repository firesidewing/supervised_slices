defmodule SupervisedSlices.Orgs.GeofenceChecker do
  require OpenTelemetry.Tracer
  @moduledoc """
  Checks whether a delivery address falls within an organization's configured
  geofence circle.

  Geocoding is performed via the free Nominatim OpenStreetMap API. If geocoding
  fails (network error, no result), the check fails open — the order is allowed
  through rather than silently rejected.
  """

  @nominatim_url "https://nominatim.openstreetmap.org/search"
  @timeout_ms 4_000

  @doc """
  Returns true if:
    - the org has no geofence configured, OR
    - the geofence is not fully set up (missing center or radius), OR
    - the address geocodes to a point within the configured radius, OR
    - geocoding fails (fail-open policy).

  Returns false only when geocoding succeeds AND the address is outside the radius.
  """
  def within_zone?(%{delivery_geo_fence: nil}, _address), do: true

  def within_zone?(%{delivery_geo_fence: fence}, address) do
    if fence_configured?(fence) do
      query = build_query(address)

      case geocode(query) do
        {:ok, lat, lng} ->
          haversine_km(fence.center_lat, fence.center_lng, lat, lng) <= fence.radius_in_km

        :error ->
          # Fail open: geocoding unavailable, don't block the order
          true
      end
    else
      true
    end
  end

  def within_zone?(_, _), do: true

  defp fence_configured?(%{center_lat: lat, center_lng: lng, radius_in_km: r})
       when not is_nil(lat) and not is_nil(lng) and not is_nil(r) and r > 0,
       do: true

  defp fence_configured?(_), do: false

  defp build_query(address) when is_map(address) do
    [
      address["street"] || address[:street],
      address["city"] || address[:city],
      address["zip"] || address[:zip]
    ]
    |> Enum.filter(&(not is_nil(&1) and &1 != ""))
    |> Enum.join(", ")
  end

  defp geocode(query) do
    url = "#{@nominatim_url}?format=json&q=#{URI.encode(query)}&limit=1"

    extra_opts = Application.get_env(:supervised_slices, :req_options, [])

    OpenTelemetry.Tracer.with_span "geofence.geocode", %{
      attributes: %{"geofence.service" => "nominatim"}
    } do
      case Req.get(
             url,
             [headers: [{"User-Agent", "SupervisedSlices/1.0"}], receive_timeout: @timeout_ms] ++
               extra_opts
           ) do
        {:ok, %{status: 200, body: [%{"lat" => lat, "lon" => lng} | _]}} ->
          with {lat_f, _} <- Float.parse(lat),
               {lng_f, _} <- Float.parse(lng) do
            {:ok, lat_f, lng_f}
          else
            _ -> :error
          end

        _ ->
          :error
      end
    end
  end

  # Haversine formula — returns distance in kilometres.
  defp haversine_km(lat1, lng1, lat2, lng2) do
    r = 6_371.0
    dlat = (lat2 - lat1) * :math.pi() / 180
    dlng = (lng2 - lng1) * :math.pi() / 180

    a =
      :math.sin(dlat / 2) ** 2 +
        :math.cos(lat1 * :math.pi() / 180) *
          :math.cos(lat2 * :math.pi() / 180) *
          :math.sin(dlng / 2) ** 2

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    r * c
  end
end
