defmodule SupervisedSlicesWeb.AdminLive.SettingsComponent do
  use SupervisedSlicesWeb, :live_component

  alias SupervisedSlices.Orgs.{LogoUploader, Organization}

  def update(%{org: org} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:tax_input, format_tax_rate(org.tax_rate))
     |> assign(:prep_time_input, to_string(org.default_prep_time))
     |> assign(:primary_color_input, org.primary_color || "#b90027")
     |> assign(:secondary_color_input, org.secondary_color || "#3a6843")
     |> assign(:delivery_enabled, org.delivery_enabled)
     |> assign(:pickup_enabled, org.pickup_enabled)
     |> assign(:delivery_fee_input, format_money(org.delivery_fee))
     |> assign(:delivery_min_order_input, format_money(org.delivery_min_order))
     |> assign(
       :geo_fence_lat,
       (org.delivery_geo_fence && to_string(org.delivery_geo_fence.center_lat)) || ""
     )
     |> assign(
       :geo_fence_lng,
       (org.delivery_geo_fence && to_string(org.delivery_geo_fence.center_lng)) || ""
     )
     |> assign(
       :geo_fence_radius,
       (org.delivery_geo_fence && to_string(org.delivery_geo_fence.radius_in_km)) || ""
     )
     |> assign(:search_address_input, "")
     |> assign(:save_status, nil)
     |> assign(:branding_status, nil)
     |> allow_upload(:logo,
       accept: ~w(.jpg .jpeg .png .gif .webp .svg),
       max_entries: 1,
       max_file_size: 5_000_000
     )}
  end

  def handle_event("update_geo_center", %{"lat" => lat, "lng" => lng}, socket) do
    {:noreply,
     socket
     |> assign(:geo_fence_lat, to_string(lat))
     |> assign(:geo_fence_lng, to_string(lng))}
  end

  def handle_event("search_address", params, socket) do
    address = params["address"] || params["value"]

    if address && address != "" do
      url =
        "https://nominatim.openstreetmap.org/search?format=json&q=#{URI.encode(address)}&limit=1"

      headers = [{"User-Agent", "SupervisedSlices"}]

      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: [%{"lat" => lat, "lon" => lng} | _]}} ->
          lat = String.to_float(lat)
          lng = String.to_float(lng)

          {:noreply,
           socket
           |> assign(:geo_fence_lat, to_string(lat))
           |> assign(:geo_fence_lng, to_string(lng))
           |> push_event("recenter_map", %{lat: lat, lng: lng})}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_radius", %{"geo_fence_radius" => radius}, socket) do
    {:noreply, assign(socket, :geo_fence_radius, radius)}
  end

  def handle_event("update_search_input", %{"address_search" => address}, socket) do
    {:noreply, assign(socket, :search_address_input, address)}
  end

  def handle_event("save_settings", params, socket) do
    %{"tax_rate" => raw_tax, "prep_time" => raw_prep} = params

    delivery_enabled = params["delivery_enabled"] == "true"
    pickup_enabled = params["pickup_enabled"] == "true"
    raw_delivery_fee = params["delivery_fee"]
    raw_delivery_min = params["delivery_min_order"]

    geo_fence = %{
      center_lat: parse_float(params["geo_fence_lat"]),
      center_lng: parse_float(params["geo_fence_lng"]),
      radius_in_km: parse_float(params["geo_fence_radius"]),
      type: :circle
    }

    with {:ok, rate} <- parse_tax_rate(raw_tax),
         {:ok, prep_time} <- parse_prep_time(raw_prep),
         {:ok, delivery_fee} <- parse_money(raw_delivery_fee),
         {:ok, delivery_min} <- parse_money(raw_delivery_min) do
      updated_org =
        Organization.update_settings!(
          socket.assigns.org,
          %{
            tax_rate: rate,
            default_prep_time: prep_time,
            delivery_enabled: delivery_enabled,
            pickup_enabled: pickup_enabled,
            delivery_fee: delivery_fee,
            delivery_min_order: delivery_min,
            delivery_geo_fence: geo_fence
          },
          authorize?: false
        )

      {:noreply,
       socket
       |> assign(:tax_input, format_tax_rate(rate))
       |> assign(:prep_time_input, to_string(prep_time))
       |> assign(:delivery_enabled, delivery_enabled)
       |> assign(:pickup_enabled, pickup_enabled)
       |> assign(:delivery_fee_input, format_money(delivery_fee))
       |> assign(:delivery_min_order_input, format_money(delivery_min))
       |> assign(:geo_fence_lat, to_string(geo_fence.center_lat))
       |> assign(:geo_fence_lng, to_string(geo_fence.center_lng))
       |> assign(:geo_fence_radius, to_string(geo_fence.radius_in_km))
       |> assign(:org, updated_org)
       |> assign(:save_status, :ok)}
    else
      _ ->
        {:noreply, assign(socket, :save_status, :error)}
    end
  end

  def handle_event(
        "save_branding",
        %{"primary_color" => primary, "secondary_color" => secondary},
        socket
      ) do
    org = socket.assigns.org

    logo_url =
      consume_uploaded_entries(socket, :logo, fn %{path: path}, entry ->
        {:ok, LogoUploader.upload(org.id, path, entry.client_type)}
      end)
      |> List.first()

    attrs =
      %{primary_color: parse_color(primary), secondary_color: parse_color(secondary)}
      |> maybe_put_logo(logo_url, org.logo_url)

    case Organization.update_branding(org, attrs, authorize?: false) do
      {:ok, updated_org} ->
        {:noreply,
         socket
         |> assign(:org, updated_org)
         |> assign(:primary_color_input, updated_org.primary_color || primary)
         |> assign(:secondary_color_input, updated_org.secondary_color || secondary)
         |> assign(:branding_status, :ok)}

      {:error, _} ->
        {:noreply, assign(socket, :branding_status, :error)}
    end
  end

  defp maybe_put_logo(attrs, nil, _existing), do: attrs
  defp maybe_put_logo(attrs, url, _existing), do: Map.put(attrs, :logo_url, url)

  defp parse_color(<<"#", _rest::binary>> = hex) when byte_size(hex) == 7, do: hex
  defp parse_color(_), do: nil

  defp parse_prep_time(raw) do
    case Integer.parse(String.trim(raw)) do
      {n, ""} when n >= 1 and n <= 120 -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_tax_rate(raw) do
    trimmed = String.trim(raw)

    case Decimal.parse(trimmed) do
      {decimal, ""} ->
        if Decimal.compare(decimal, Decimal.new("0")) != :lt &&
             Decimal.compare(decimal, Decimal.new("100")) != :gt do
          rate = Decimal.div(decimal, Decimal.new("100"))
          {:ok, rate}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp format_tax_rate(rate) do
    rate
    |> Decimal.mult(Decimal.new("100"))
    |> Decimal.normalize()
    |> Decimal.to_string()
  end

  defp format_money(nil), do: ""

  defp format_money(money) do
    money.amount
    |> Decimal.normalize()
    |> Decimal.to_string()
  end

  defp parse_money(raw) do
    case Decimal.parse(String.trim(raw || "0")) do
      {decimal, ""} -> {:ok, Money.new(decimal, :CAD)}
      _ -> :error
    end
  end

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil

  defp parse_float(raw) do
    case Float.parse(raw) do
      {float, _} -> float
      _ -> nil
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto px-10 py-10 space-y-6">
      <div class="bg-white rounded-3xl shadow-sm p-8 space-y-6">
        <div>
          <h2 class="font-headline text-lg font-extrabold text-on-surface">
            Kitchen Settings
          </h2>
          <p class="font-body text-sm text-on-surface-variant mt-1">
            Configure defaults for orders and tax.
          </p>
        </div>

        <form phx-submit="save_settings" phx-target={@myself} class="space-y-4">
          <div>
            <label class="font-body block text-xs font-bold uppercase tracking-widest text-on-surface-variant mb-1.5">
              Default Prep Time (minutes)
            </label>
            <div class="relative">
              <input
                type="text"
                name="prep_time"
                value={@prep_time_input}
                placeholder="e.g. 20"
                class="w-full px-4 py-3 pr-14 rounded-xl bg-surface-container-low border-0 text-on-surface placeholder-on-surface-variant/50 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-primary/40"
              />
              <span class="absolute right-4 top-1/2 -translate-y-1/2 text-on-surface-variant font-bold text-sm">
                min
              </span>
            </div>
            <p class="font-body text-xs text-on-surface-variant mt-1.5">
              Shown to customers as their estimated wait time. Between 1–120 min.
            </p>
          </div>

          <div>
            <label class="font-body block text-xs font-bold uppercase tracking-widest text-on-surface-variant mb-1.5">
              Tax Rate (%)
            </label>
            <div class="relative">
              <input
                type="text"
                name="tax_rate"
                value={@tax_input}
                placeholder="e.g. 8.75"
                class="w-full px-4 py-3 pr-10 rounded-xl bg-surface-container-low border-0 text-on-surface placeholder-on-surface-variant/50 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-primary/40"
              />
              <span class="absolute right-4 top-1/2 -translate-y-1/2 text-on-surface-variant font-bold text-sm">
                %
              </span>
            </div>
            <p class="font-body text-xs text-on-surface-variant mt-1.5">
              Applied to every order at checkout. Enter 0 to disable tax.
            </p>
          </div>

          <div class="pt-6 border-t border-surface-container/50 space-y-6">
            <div>
              <h3 class="font-headline text-base font-extrabold text-on-surface">
                Delivery & Pickup
              </h3>
              <p class="font-body text-xs text-on-surface-variant mt-1">
                Configure delivery area and fees.
              </p>
            </div>

            <div class="flex gap-8">
              <label class="flex items-center gap-3 font-body text-sm font-bold text-on-surface cursor-pointer group">
                <input
                  type="checkbox"
                  name="delivery_enabled"
                  value="true"
                  checked={@delivery_enabled}
                  class="w-5 h-5 rounded-lg border-2 border-surface-container text-primary focus:ring-primary/20 transition-all cursor-pointer"
                />
                <span>Delivery</span>
              </label>
              <label class="flex items-center gap-3 font-body text-sm font-bold text-on-surface cursor-pointer group">
                <input
                  type="checkbox"
                  name="pickup_enabled"
                  value="true"
                  checked={@pickup_enabled}
                  class="w-5 h-5 rounded-lg border-2 border-surface-container text-primary focus:ring-primary/20 transition-all cursor-pointer"
                />
                <span>Pickup</span>
              </label>
            </div>

            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="font-body block text-xs font-bold uppercase tracking-widest text-on-surface-variant mb-1.5">
                  Delivery Fee
                </label>
                <div class="relative">
                  <span class="absolute left-4 top-1/2 -translate-y-1/2 text-on-surface-variant font-bold text-sm">
                    $
                  </span>
                  <input
                    type="text"
                    name="delivery_fee"
                    value={@delivery_fee_input}
                    placeholder="0.00"
                    class="w-full pl-8 pr-4 py-3 rounded-xl bg-surface-container-low border-0 text-on-surface placeholder-on-surface-variant/50 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-primary/40"
                  />
                </div>
              </div>
              <div>
                <label class="font-body block text-xs font-bold uppercase tracking-widest text-on-surface-variant mb-1.5">
                  Min. Order
                </label>
                <div class="relative">
                  <span class="absolute left-4 top-1/2 -translate-y-1/2 text-on-surface-variant font-bold text-sm">
                    $
                  </span>
                  <input
                    type="text"
                    name="delivery_min_order"
                    value={@delivery_min_order_input}
                    placeholder="0.00"
                    class="w-full pl-8 pr-4 py-3 rounded-xl bg-surface-container-low border-0 text-on-surface placeholder-on-surface-variant/50 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-primary/40"
                  />
                </div>
              </div>
            </div>

            <div class="space-y-4 p-5 bg-surface-container-lowest/50 rounded-2xl border border-surface-container/30">
              <label class="font-body block text-[10px] font-black uppercase tracking-[0.15em] text-on-surface-variant">
                Delivery Geo-fence (Circle)
              </label>

              <div class="space-y-2">
                <label class="text-[10px] font-bold uppercase tracking-wider text-on-surface-variant/70 ml-1">
                  Search Center Address
                </label>
                <div class="flex gap-2">
                  <input
                    type="text"
                    name="address_search"
                    id="address_search"
                    value={@search_address_input}
                    placeholder="Enter an address..."
                    class="flex-1 px-4 py-2.5 rounded-xl bg-surface-container-low border-0 text-sm font-medium focus:ring-2 focus:ring-primary/40"
                    phx-keydown="search_address"
                    phx-key="Enter"
                    phx-change="update_search_input"
                    phx-target={@myself}
                  />
                  <button
                    type="button"
                    phx-click="search_address"
                    phx-value-address={@search_address_input}
                    phx-target={@myself}
                    class="px-4 py-2 bg-surface-container text-on-surface rounded-xl text-xs font-bold uppercase tracking-widest hover:bg-surface-container-high transition-colors"
                  >
                    Search
                  </button>
                </div>
              </div>

              <div
                id="geofence-map"
                phx-update="ignore"
                phx-hook="GeoFenceMap"
                data-lat={@geo_fence_lat}
                data-lng={@geo_fence_lng}
                data-radius={@geo_fence_radius}
                class="w-full h-64 rounded-2xl border-2 border-surface-container overflow-hidden"
              >
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div class="space-y-1">
                  <label class="text-[10px] font-bold uppercase tracking-wider text-on-surface-variant/70 ml-1">
                    Latitude
                  </label>
                  <input
                    type="text"
                    name="geo_fence_lat"
                    value={@geo_fence_lat}
                    placeholder="e.g. 40.7128"
                    class="w-full px-4 py-2.5 rounded-xl bg-surface-container-low border-0 text-sm font-medium focus:ring-2 focus:ring-primary/40"
                  />
                </div>
                <div class="space-y-1">
                  <label class="text-[10px] font-bold uppercase tracking-wider text-on-surface-variant/70 ml-1">
                    Longitude
                  </label>
                  <input
                    type="text"
                    name="geo_fence_lng"
                    value={@geo_fence_lng}
                    placeholder="e.g. -74.0060"
                    class="w-full px-4 py-2.5 rounded-xl bg-surface-container-low border-0 text-sm font-medium focus:ring-2 focus:ring-primary/40"
                  />
                </div>
              </div>
              <div class="space-y-1">
                <label class="text-[10px] font-bold uppercase tracking-wider text-on-surface-variant/70 ml-1">
                  Radius (km)
                </label>
                <input
                  type="text"
                  name="geo_fence_radius"
                  value={@geo_fence_radius}
                  phx-change="update_radius"
                  phx-target={@myself}
                  placeholder="e.g. 5.0"
                  class="w-full px-4 py-2.5 rounded-xl bg-surface-container-low border-0 text-sm font-medium focus:ring-2 focus:ring-primary/40"
                />
              </div>
            </div>
          </div>

          <%= if @save_status == :ok do %>
            <p class="text-sm text-secondary font-medium">Settings saved.</p>
          <% end %>
          <%= if @save_status == :error do %>
            <p class="text-sm text-primary font-medium">
              Check your values: prep time 1–120 min, tax 0–100%.
            </p>
          <% end %>

          <button
            type="submit"
            class="w-full bg-gradient-to-r from-primary to-primary-container text-white font-bold py-3 rounded-full text-sm uppercase tracking-widest hover:scale-[1.02] transition-all active:scale-95 shadow-[0px_8px_24px_rgba(185,0,39,0.25)]"
          >
            Save
          </button>
        </form>
      </div>

      <div class="bg-white rounded-3xl shadow-sm p-8 space-y-6">
        <div>
          <h2 class="font-headline text-lg font-extrabold text-on-surface">
            Branding
          </h2>
          <p class="font-body text-sm text-on-surface-variant mt-1">
            Customise the logo and colours shown to staff and customers.
          </p>
        </div>

        <form phx-submit="save_branding" phx-target={@myself} class="space-y-5">
          <div>
            <label class="font-body block text-xs font-bold uppercase tracking-widest text-on-surface-variant mb-1.5">
              Logo
            </label>
            <%= if @org.logo_url do %>
              <div class="mb-3 p-3 bg-surface-container-low rounded-xl inline-block">
                <img src={@org.logo_url} alt="Current logo" class="h-12 object-contain" />
              </div>
            <% end %>
            <.live_file_input
              upload={@uploads.logo}
              class="w-full text-sm text-on-surface-variant file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-xs file:font-bold file:uppercase file:tracking-widest file:bg-surface-container file:text-on-surface hover:file:bg-surface-container-high cursor-pointer"
            />
            <p class="font-body text-xs text-on-surface-variant mt-1.5">
              Accepted: JPG, PNG, GIF, WebP, SVG — max 5 MB.
            </p>
          </div>

          <div>
            <label class="font-body block text-xs font-bold uppercase tracking-widest text-on-surface-variant mb-1.5">
              Primary Colour
            </label>
            <div class="flex items-center gap-3">
              <input
                type="color"
                name="primary_color"
                value={@primary_color_input}
                class="w-12 h-10 rounded-lg border-0 cursor-pointer bg-transparent p-0.5"
              />
              <span class="font-body text-sm text-on-surface-variant">{@primary_color_input}</span>
            </div>
            <p class="font-body text-xs text-on-surface-variant mt-1.5">
              Used for buttons, headings, and accent elements.
            </p>
          </div>

          <div>
            <label class="font-body block text-xs font-bold uppercase tracking-widest text-on-surface-variant mb-1.5">
              Secondary Colour
            </label>
            <div class="flex items-center gap-3">
              <input
                type="color"
                name="secondary_color"
                value={@secondary_color_input}
                class="w-12 h-10 rounded-lg border-0 cursor-pointer bg-transparent p-0.5"
              />
              <span class="font-body text-sm text-on-surface-variant">{@secondary_color_input}</span>
            </div>
            <p class="font-body text-xs text-on-surface-variant mt-1.5">
              Used for badges and availability indicators.
            </p>
          </div>

          <%= if @branding_status == :ok do %>
            <p class="text-sm text-secondary font-medium">Branding saved.</p>
          <% end %>
          <%= if @branding_status == :error do %>
            <p class="text-sm text-primary font-medium">
              Colour values must be valid hex colours (e.g. #ff0000).
            </p>
          <% end %>

          <button
            type="submit"
            class="w-full bg-gradient-to-r from-primary to-primary-container text-white font-bold py-3 rounded-full text-sm uppercase tracking-widest hover:scale-[1.02] transition-all active:scale-95 shadow-[0px_8px_24px_rgba(185,0,39,0.25)]"
          >
            Save Branding
          </button>
        </form>
      </div>
    </div>
    """
  end
end
