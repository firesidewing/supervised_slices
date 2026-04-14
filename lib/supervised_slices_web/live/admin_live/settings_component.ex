defmodule SupervisedSlicesWeb.AdminLive.SettingsComponent do
  use SupervisedSlicesWeb, :live_component

  require Ash.Query

  alias SupervisedSlices.Orgs.{LogoUploader, Organization}

  def update(%{org: org, current_user: current_user} = assigns, socket) do
    memberships = load_memberships(org.id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:current_user, current_user)
     |> assign(:memberships, memberships)
     |> assign(:invite_email, "")
     |> assign(:invite_role, :staff)
     |> assign(:invite_status, nil)
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
     |> assign(:schedule, org.operating_schedule)
     |> assign(:timezone, org.timezone || "Etc/UTC")
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
    timezone = params["timezone"] || "Etc/UTC"

    geo_fence = %{
      center_lat: parse_float(params["geo_fence_lat"]),
      center_lng: parse_float(params["geo_fence_lng"]),
      radius_in_km: parse_float(params["geo_fence_radius"]),
      type: :circle
    }

    schedule = parse_schedule_params(params)

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
            delivery_geo_fence: geo_fence,
            operating_schedule: schedule,
            timezone: timezone
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
       |> assign(:schedule, updated_org.operating_schedule)
       |> assign(:timezone, updated_org.timezone || "Etc/UTC")
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

  def handle_event("invite_member", %{"email" => email, "role" => role_str}, socket) do
    role = String.to_existing_atom(role_str)
    org = socket.assigns.org

    result =
      SupervisedSlices.Orgs.Membership
      |> Ash.Changeset.for_create(:invite, %{email: email, role: role, organization_id: org.id})
      |> Ash.create(actor: socket.assigns.current_user)

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:memberships, load_memberships(org.id))
         |> assign(:invite_email, "")
         |> assign(:invite_status, :ok)}

      {:error, _} ->
        {:noreply, assign(socket, :invite_status, :error)}
    end
  end

  def handle_event("remove_member", %{"id" => membership_id}, socket) do
    membership = Enum.find(socket.assigns.memberships, &(&1.id == membership_id))
    Ash.destroy!(membership, authorize?: false)
    {:noreply, assign(socket, :memberships, load_memberships(socket.assigns.org.id))}
  end

  def handle_event("update_member_role", %{"id" => membership_id, "role" => role_str}, socket) do
    role = String.to_existing_atom(role_str)
    membership = Enum.find(socket.assigns.memberships, &(&1.id == membership_id))

    membership
    |> Ash.Changeset.for_update(:update_role, %{role: role})
    |> Ash.update!(authorize?: false)

    {:noreply, assign(socket, :memberships, load_memberships(socket.assigns.org.id))}
  end

  defp load_memberships(org_id) do
    SupervisedSlices.Orgs.Membership
    |> Ash.Query.filter(organization_id == ^org_id and role in [:admin, :staff])
    |> Ash.Query.load([:user])
    |> Ash.read!(authorize?: false)
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

  @days ~w(mon tue wed thu fri sat sun)

  defp parse_schedule_params(params) do
    @days
    |> Enum.flat_map(fn day ->
      is_open = params["#{day}_open"] == "true"
      open_time = String.trim(params["#{day}_open_time"] || "11:00")
      close_time = String.trim(params["#{day}_close_time"] || "22:00")

      [
        {:"#{day}_open", is_open},
        {:"#{day}_open_time", open_time},
        {:"#{day}_close_time", close_time}
      ]
    end)
    |> Map.new()
  end

  defp schedule_day_value(nil, _key, default), do: default
  defp schedule_day_value(schedule, key, default), do: Map.get(schedule, key) || default

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil

  defp parse_float(raw) do
    case Float.parse(raw) do
      {float, _} -> float
      _ -> nil
    end
  end

  defp timezone_options do
    [
      {"UTC", [{"UTC", "Etc/UTC"}]},
      {"Canada",
       [
         {"Newfoundland (UTC-3:30)", "America/St_Johns"},
         {"Atlantic — Halifax (UTC-4)", "America/Halifax"},
         {"Eastern — Toronto (UTC-5)", "America/Toronto"},
         {"Central — Winnipeg (UTC-6)", "America/Winnipeg"},
         {"Mountain — Edmonton (UTC-7)", "America/Edmonton"},
         {"Pacific — Vancouver (UTC-8)", "America/Vancouver"}
       ]},
      {"United States",
       [
         {"Eastern — New York (UTC-5)", "America/New_York"},
         {"Central — Chicago (UTC-6)", "America/Chicago"},
         {"Mountain — Denver (UTC-7)", "America/Denver"},
         {"Arizona, no DST (UTC-7)", "America/Phoenix"},
         {"Pacific — Los Angeles (UTC-8)", "America/Los_Angeles"},
         {"Alaska (UTC-9)", "America/Anchorage"},
         {"Hawaii (UTC-10)", "Pacific/Honolulu"}
       ]},
      {"Latin America",
       [
         {"Mexico City (UTC-6)", "America/Mexico_City"},
         {"São Paulo (UTC-3)", "America/Sao_Paulo"},
         {"Buenos Aires (UTC-3)", "America/Argentina/Buenos_Aires"}
       ]},
      {"Europe",
       [
         {"London (UTC+0)", "Europe/London"},
         {"Paris / Berlin / Rome (UTC+1)", "Europe/Paris"},
         {"Helsinki / Kiev (UTC+2)", "Europe/Helsinki"},
         {"Moscow (UTC+3)", "Europe/Moscow"}
       ]},
      {"Asia / Pacific",
       [
         {"Dubai (UTC+4)", "Asia/Dubai"},
         {"India (UTC+5:30)", "Asia/Kolkata"},
         {"Bangkok (UTC+7)", "Asia/Bangkok"},
         {"Singapore / Shanghai (UTC+8)", "Asia/Singapore"},
         {"Tokyo / Seoul (UTC+9)", "Asia/Tokyo"},
         {"Sydney / Melbourne (UTC+10)", "Australia/Sydney"},
         {"New Zealand (UTC+12)", "Pacific/Auckland"}
       ]}
    ]
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto space-y-12 pb-24">
      <div class="bg-surface-container-low rounded-md shadow-sm p-10 space-y-10">
        <div>
          <h2 class="font-headline text-2xl font-black text-on-surface">
            System Settings
          </h2>
          <p class="font-body text-sm text-on-surface-variant/60 mt-1 italic">
            Configure defaults for orders and tax.
          </p>
        </div>

        <form phx-submit="save_settings" phx-target={@myself} class="space-y-8">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
            <div>
              <label class="font-body block text-[10px] font-black uppercase tracking-[0.2em] text-on-surface-variant/40 mb-2">
                Default Prep Time (minutes)
              </label>
              <div class="relative">
                <input
                  type="text"
                  name="prep_time"
                  value={@prep_time_input}
                  placeholder="e.g. 20"
                  class="w-full px-4 py-3 pr-14 rounded bg-surface-container-highest border-0 text-on-surface placeholder-on-surface-variant/30 text-sm font-bold focus:outline-none focus:ring-1 focus:ring-primary"
                />
                <span class="absolute right-4 top-1/2 -translate-y-1/2 text-on-surface-variant/40 font-bold text-[10px] uppercase">
                  min
                </span>
              </div>
            </div>

            <div>
              <label class="font-body block text-[10px] font-black uppercase tracking-[0.2em] text-on-surface-variant/40 mb-2">
                Tax Rate (%)
              </label>
              <div class="relative">
                <input
                  type="text"
                  name="tax_rate"
                  value={@tax_input}
                  placeholder="e.g. 8.75"
                  class="w-full px-4 py-3 pr-10 rounded bg-surface-container-highest border-0 text-on-surface placeholder-on-surface-variant/30 text-sm font-bold focus:outline-none focus:ring-1 focus:ring-primary"
                />
                <span class="absolute right-4 top-1/2 -translate-y-1/2 text-on-surface-variant/40 font-bold text-sm">
                  %
                </span>
              </div>
            </div>
          </div>

          <div class="pt-10 border-t border-on-surface/5 space-y-8">
            <div>
              <h3 class="font-headline text-lg font-black text-on-surface">
                Fulfillment Channels
              </h3>
              <p class="font-body text-xs text-on-surface-variant/60 mt-1">
                Configure delivery area and fees.
              </p>
            </div>

            <div class="flex gap-12">
              <label class="flex items-center gap-3 font-body text-sm font-bold text-on-surface cursor-pointer group">
                <input
                  type="checkbox"
                  name="delivery_enabled"
                  value="true"
                  checked={@delivery_enabled}
                  class="w-5 h-5 rounded border-2 border-surface-container-highest text-primary focus:ring-primary/20 transition-all cursor-pointer"
                />
                <span class="uppercase tracking-widest text-[10px]">Delivery</span>
              </label>
              <label class="flex items-center gap-3 font-body text-sm font-bold text-on-surface cursor-pointer group">
                <input
                  type="checkbox"
                  name="pickup_enabled"
                  value="true"
                  checked={@pickup_enabled}
                  class="w-5 h-5 rounded border-2 border-surface-container-highest text-primary focus:ring-primary/20 transition-all cursor-pointer"
                />
                <span class="uppercase tracking-widest text-[10px]">Pickup</span>
              </label>
            </div>

            <div class="grid grid-cols-2 gap-8">
              <div>
                <label class="font-body block text-[10px] font-black uppercase tracking-[0.2em] text-on-surface-variant/40 mb-2">
                  Delivery Fee
                </label>
                <div class="relative">
                  <span class="absolute left-4 top-1/2 -translate-y-1/2 text-on-surface-variant/40 font-bold text-sm">
                    $
                  </span>
                  <input
                    type="text"
                    name="delivery_fee"
                    value={@delivery_fee_input}
                    placeholder="0.00"
                    class="w-full pl-8 pr-4 py-3 rounded bg-surface-container-highest border-0 text-on-surface placeholder-on-surface-variant/30 text-sm font-bold focus:outline-none focus:ring-1 focus:ring-primary"
                  />
                </div>
              </div>
              <div>
                <label class="font-body block text-[10px] font-black uppercase tracking-[0.2em] text-on-surface-variant/40 mb-2">
                  Min. Order
                </label>
                <div class="relative">
                  <span class="absolute left-4 top-1/2 -translate-y-1/2 text-on-surface-variant/40 font-bold text-sm">
                    $
                  </span>
                  <input
                    type="text"
                    name="delivery_min_order"
                    value={@delivery_min_order_input}
                    placeholder="0.00"
                    class="w-full pl-8 pr-4 py-3 rounded bg-surface-container-highest border-0 text-on-surface placeholder-on-surface-variant/30 text-sm font-bold focus:outline-none focus:ring-1 focus:ring-primary"
                  />
                </div>
              </div>
            </div>

            <div class="space-y-4 p-6 bg-surface-container-highest/20 rounded-md border border-on-surface/5">
              <label class="font-body block text-[10px] font-black uppercase tracking-[0.2em] text-primary/60">
                Delivery Geo-fence
              </label>

              <div class="space-y-2">
                <div class="flex gap-2">
                  <input
                    type="text"
                    name="address_search"
                    id="address_search"
                    value={@search_address_input}
                    placeholder="Search center address..."
                    class="flex-1 px-4 py-2.5 rounded bg-surface-container-highest border-0 text-sm font-bold focus:ring-1 focus:ring-primary outline-none"
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
                    class="px-6 py-2 bg-primary text-white rounded-md text-[10px] font-black uppercase tracking-widest hover:opacity-90 transition-all active:scale-95"
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
                class="w-full h-64 rounded border border-on-surface/5 overflow-hidden"
              >
              </div>

              <div class="grid grid-cols-3 gap-4">
                <div class="space-y-1">
                  <label class="text-[9px] font-black uppercase tracking-widest text-on-surface-variant/40 ml-1">
                    Latitude
                  </label>
                  <input
                    type="text"
                    name="geo_fence_lat"
                    value={@geo_fence_lat}
                    class="w-full px-4 py-2.5 rounded bg-surface-container-highest border-0 text-xs font-bold focus:ring-1 focus:ring-primary"
                  />
                </div>
                <div class="space-y-1">
                  <label class="text-[9px] font-black uppercase tracking-widest text-on-surface-variant/40 ml-1">
                    Longitude
                  </label>
                  <input
                    type="text"
                    name="geo_fence_lng"
                    value={@geo_fence_lng}
                    class="w-full px-4 py-2.5 rounded bg-surface-container-highest border-0 text-xs font-bold focus:ring-1 focus:ring-primary"
                  />
                </div>
                <div class="space-y-1">
                  <label class="text-[9px] font-black uppercase tracking-widest text-on-surface-variant/40 ml-1">
                    Radius (km)
                  </label>
                  <input
                    type="text"
                    name="geo_fence_radius"
                    value={@geo_fence_radius}
                    phx-change="update_radius"
                    phx-target={@myself}
                    class="w-full px-4 py-2.5 rounded bg-surface-container-highest border-0 text-xs font-bold focus:ring-1 focus:ring-primary"
                  />
                </div>
              </div>
            </div>
          </div>

          <div class="pt-10 border-t border-on-surface/5 space-y-6">
            <div>
              <h3 class="font-headline text-lg font-black text-on-surface">
                Operating Schedule
              </h3>
              <p class="font-body text-xs text-on-surface-variant/60 mt-1 italic">
                Set your kitchen's open hours.
              </p>
            </div>

            <div>
              <label class="font-body block text-[10px] font-black uppercase tracking-[0.2em] text-on-surface-variant/40 mb-2">
                Timezone
              </label>
              <select
                name="timezone"
                class="w-full px-4 py-3 rounded bg-surface-container-highest border-0 text-on-surface text-sm font-bold focus:outline-none focus:ring-1 focus:ring-primary"
              >
                <%= for {group, zones} <- timezone_options() do %>
                  <optgroup label={group} class="font-bold text-xs uppercase tracking-widest">
                    <%= for {label, value} <- zones do %>
                      <option value={value} selected={@timezone == value}>{label}</option>
                    <% end %>
                  </optgroup>
                <% end %>
              </select>
            </div>

            <% days = [
              {"mon", "Monday"},
              {"tue", "Tuesday"},
              {"wed", "Wednesday"},
              {"thu", "Thursday"},
              {"fri", "Friday"},
              {"sat", "Saturday"},
              {"sun", "Sunday"}
            ] %>

            <div class="space-y-2 pt-4">
              <%= for {key, label} <- days do %>
                <% is_open = schedule_day_value(@schedule, :"#{key}_open", key not in ["sun"]) %>
                <% open_time = schedule_day_value(@schedule, :"#{key}_open_time", "11:00") %>
                <% close_time = schedule_day_value(@schedule, :"#{key}_close_time", "22:00") %>

                <div class="flex items-center gap-4 py-2 border-b border-on-surface/5 last:border-0">
                  <span class="font-body text-[10px] font-black text-on-surface-variant w-24 uppercase tracking-widest">
                    {label}
                  </span>

                  <input type="hidden" name={"#{key}_open"} value="false" />
                  <label class="flex items-center gap-2 cursor-pointer group">
                    <input
                      type="checkbox"
                      name={"#{key}_open"}
                      value="true"
                      checked={is_open}
                      class="rounded border-2 border-surface-container-highest text-primary focus:ring-primary/20 w-4 h-4"
                    />
                    <span class="text-[10px] font-black uppercase tracking-widest text-on-surface-variant/40 group-hover:text-primary transition-colors">
                      Open
                    </span>
                  </label>

                  <div class="flex-1 flex items-center justify-end gap-3">
                    <input
                      type="time"
                      name={"#{key}_open_time"}
                      value={open_time}
                      class="rounded bg-surface-container-highest border-0 text-xs font-bold px-3 py-1.5 text-on-surface focus:ring-1 focus:ring-primary outline-none"
                    />
                    <span class="text-[10px] font-black text-on-surface-variant/20 uppercase">
                      to
                    </span>
                    <input
                      type="time"
                      name={"#{key}_close_time"}
                      value={close_time}
                      class="rounded bg-surface-container-highest border-0 text-xs font-bold px-3 py-1.5 text-on-surface focus:ring-1 focus:ring-primary outline-none"
                    />
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <div class="pt-10 flex flex-col gap-4">
            <%= if @save_status == :ok do %>
              <p class="text-[10px] font-black uppercase tracking-[0.2em] text-secondary text-center">
                Settings saved successfully
              </p>
            <% end %>
            <%= if @save_status == :error do %>
              <p class="text-[10px] font-black uppercase tracking-[0.2em] text-primary text-center">
                Invalid input values
              </p>
            <% end %>

            <button
              type="submit"
              class="w-full bg-primary text-white font-black py-4 rounded-md text-xs uppercase tracking-[0.2em] transition-all active:scale-95 shadow-lg shadow-primary/10"
            >
              Commit Settings
            </button>
          </div>
        </form>
      </div>

      <div class="bg-surface-container-low rounded-md shadow-sm p-10 space-y-10">
        <div>
          <h2 class="font-headline text-2xl font-black text-on-surface">
            Visual Atelier
          </h2>
          <p class="font-body text-sm text-on-surface-variant/60 mt-1 italic">
            Customize the artisan identity.
          </p>
        </div>

        <form phx-submit="save_branding" phx-target={@myself} class="space-y-8">
          <div>
            <label class="font-body block text-[10px] font-black uppercase tracking-[0.2em] text-on-surface-variant/40 mb-4">
              Brand Mark (Logo)
            </label>
            <div class="flex items-center gap-8">
              <%= if @org.logo_url do %>
                <div class="p-4 bg-surface-container-highest rounded-md shrink-0">
                  <img src={@org.logo_url} alt="Current logo" class="h-16 w-auto object-contain" />
                </div>
              <% end %>
              <div class="flex-1">
                <.live_file_input
                  upload={@uploads.logo}
                  class="w-full text-xs text-on-surface-variant/60 file:mr-4 file:py-2 file:px-6 file:rounded file:border-0 file:text-[10px] file:font-black file:uppercase file:tracking-[0.2em] file:bg-primary file:text-white file:cursor-pointer hover:file:opacity-90"
                />
                <p class="font-body text-[9px] text-on-surface-variant/40 mt-3 uppercase tracking-widest leading-relaxed">
                  JPG, PNG, WebP — max 5 MB. Transparent SVG recommended.
                </p>
              </div>
            </div>
          </div>

          <div class="grid grid-cols-2 gap-8 pt-4">
            <div>
              <label class="font-body block text-[10px] font-black uppercase tracking-[0.2em] text-on-surface-variant/40 mb-3">
                Primary Brand Hue
              </label>
              <div class="flex items-center gap-4 p-3 bg-surface-container-highest rounded-md">
                <input
                  type="color"
                  name="primary_color"
                  value={@primary_color_input}
                  class="w-10 h-10 rounded cursor-pointer bg-transparent p-0"
                />
                <span class="font-body text-xs font-black uppercase tracking-widest text-on-surface">
                  {@primary_color_input}
                </span>
              </div>
            </div>

            <div>
              <label class="font-body block text-[10px] font-black uppercase tracking-[0.2em] text-on-surface-variant/40 mb-3">
                Secondary Accent
              </label>
              <div class="flex items-center gap-4 p-3 bg-surface-container-highest rounded-md">
                <input
                  type="color"
                  name="secondary_color"
                  value={@secondary_color_input}
                  class="w-10 h-10 rounded cursor-pointer bg-transparent p-0"
                />
                <span class="font-body text-xs font-black uppercase tracking-widest text-on-surface">
                  {@secondary_color_input}
                </span>
              </div>
            </div>
          </div>

          <div class="pt-10 flex flex-col gap-4">
            <%= if @branding_status == :ok do %>
              <p class="text-[10px] font-black uppercase tracking-[0.2em] text-secondary text-center">
                Branding updated
              </p>
            <% end %>
            <%= if @branding_status == :error do %>
              <p class="text-[10px] font-black uppercase tracking-[0.2em] text-primary text-center">
                Invalid hex values
              </p>
            <% end %>

            <button
              type="submit"
              class="w-full bg-primary text-white font-black py-4 rounded-md text-xs uppercase tracking-[0.2em] transition-all active:scale-95 shadow-lg shadow-primary/10"
            >
              Update Identity
            </button>
          </div>
        </form>
      </div>

      <div class="bg-surface-container-low rounded-md shadow-sm p-10 space-y-10">
        <div>
          <h2 class="font-headline text-2xl font-black text-on-surface">
            Artisan Team
          </h2>
          <p class="font-body text-sm text-on-surface-variant/60 mt-1 italic">
            Manage your kitchen staff.
          </p>
        </div>

        <div class="space-y-4">
          <%= for m <- @memberships do %>
            <div class="flex items-center justify-between gap-6 py-4 border-b border-on-surface/5 last:border-0">
              <div class="min-w-0 flex-1">
                <p class="font-body text-sm font-black text-on-surface truncate">
                  {to_string(m.user.email)}
                </p>
                <p class="text-[9px] font-black uppercase tracking-widest text-on-surface-variant/40">
                  Joined {Calendar.strftime(m.inserted_at, "%b %d, %Y")}
                </p>
              </div>
              <div class="flex items-center gap-4 shrink-0">
                <select
                  phx-change="update_member_role"
                  phx-value-id={m.id}
                  phx-target={@myself}
                  name="role"
                  class="rounded bg-surface-container-highest border-0 text-[10px] font-black uppercase tracking-widest px-3 py-1.5 text-on-surface focus:ring-1 focus:ring-primary outline-none"
                >
                  <option value="admin" selected={m.role == :admin}>Admin</option>
                  <option value="staff" selected={m.role == :staff}>Staff</option>
                </select>
                <button
                  type="button"
                  phx-click="remove_member"
                  phx-value-id={m.id}
                  phx-target={@myself}
                  class="p-1.5 text-on-surface-variant/20 hover:text-primary transition-colors"
                >
                  <span class="material-symbols-outlined text-lg">close</span>
                </button>
              </div>
            </div>
          <% end %>
        </div>

        <form
          phx-submit="invite_member"
          phx-target={@myself}
          class="space-y-6 pt-10 border-t border-on-surface/5"
        >
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label class="font-body block text-[10px] font-black uppercase tracking-[0.2em] text-on-surface-variant/40 mb-2">
                Invite by Email
              </label>
              <input
                type="email"
                name="email"
                value={@invite_email}
                placeholder="team@example.com"
                required
                class="w-full px-4 py-3 rounded bg-surface-container-highest border-0 text-sm font-bold focus:ring-1 focus:ring-primary"
              />
            </div>

            <div>
              <label class="font-body block text-[10px] font-black uppercase tracking-[0.2em] text-on-surface-variant/40 mb-2">
                Role
              </label>
              <select
                name="role"
                class="w-full px-4 py-3 rounded bg-surface-container-highest border-0 text-sm font-bold focus:ring-1 focus:ring-primary"
              >
                <option value="staff" selected={@invite_role == :staff}>Staff — orders only</option>
                <option value="admin" selected={@invite_role == :admin}>Admin — full access</option>
              </select>
            </div>
          </div>

          <div class="flex flex-col gap-4">
            <%= if @invite_status == :ok do %>
              <p class="text-[10px] font-black uppercase tracking-[0.2em] text-secondary text-center">
                Invitation sent
              </p>
            <% end %>
            <%= if @invite_status == :error do %>
              <p class="text-[10px] font-black uppercase tracking-[0.2em] text-primary text-center">
                Failed to send invitation
              </p>
            <% end %>

            <button
              type="submit"
              class="w-full bg-primary text-white font-black py-4 rounded-md text-xs uppercase tracking-[0.2em] transition-all active:scale-95 shadow-lg shadow-primary/10"
            >
              Send Invite
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
