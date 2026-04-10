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
     |> assign(:save_status, nil)
     |> assign(:branding_status, nil)
     |> allow_upload(:logo,
       accept: ~w(.jpg .jpeg .png .gif .webp .svg),
       max_entries: 1,
       max_file_size: 5_000_000
     )}
  end

  def handle_event("save_settings", %{"tax_rate" => raw_tax, "prep_time" => raw_prep}, socket) do
    with {:ok, rate} <- parse_tax_rate(raw_tax),
         {:ok, prep_time} <- parse_prep_time(raw_prep) do
      Organization.update_settings!(
        socket.assigns.org,
        %{tax_rate: rate, default_prep_time: prep_time},
        authorize?: false
      )

      {:noreply,
       socket
       |> assign(:tax_input, format_tax_rate(rate))
       |> assign(:prep_time_input, to_string(prep_time))
       |> assign(:org, %{socket.assigns.org | tax_rate: rate, default_prep_time: prep_time})
       |> assign(:save_status, :ok)}
    else
      :error ->
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
