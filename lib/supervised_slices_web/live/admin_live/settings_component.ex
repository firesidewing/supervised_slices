defmodule SupervisedSlicesWeb.AdminLive.SettingsComponent do
  use SupervisedSlicesWeb, :live_component

  alias SupervisedSlices.Orgs.Organization

  def update(%{org: org} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:tax_input, format_tax_rate(org.tax_rate))
     |> assign(:save_status, nil)}
  end

  def handle_event("save_settings", %{"tax_rate" => raw}, socket) do
    case parse_tax_rate(raw) do
      {:ok, rate} ->
        Organization.update_settings!(socket.assigns.org, %{tax_rate: rate}, authorize?: false)

        {:noreply,
         socket
         |> assign(:tax_input, format_tax_rate(rate))
         |> assign(:org, %{socket.assigns.org | tax_rate: rate})
         |> assign(:save_status, :ok)}

      :error ->
        {:noreply, assign(socket, :save_status, :error)}
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
    <div class="max-w-lg mx-auto px-10 py-10">
      <div class="bg-white rounded-3xl shadow-sm p-8 space-y-6">
        <div>
          <h2 class="font-headline text-lg font-extrabold text-on-surface">
            Tax Settings
          </h2>
          <p class="font-body text-sm text-on-surface-variant mt-1">
            Applied to every order at checkout. Enter 0 to disable tax.
          </p>
        </div>

        <form phx-submit="save_settings" phx-target={@myself} class="space-y-4">
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
          </div>

          <%= if @save_status == :ok do %>
            <p class="text-sm text-secondary font-medium">Tax rate saved.</p>
          <% end %>
          <%= if @save_status == :error do %>
            <p class="text-sm text-primary font-medium">
              Enter a valid percentage between 0 and 100.
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
    </div>
    """
  end
end
