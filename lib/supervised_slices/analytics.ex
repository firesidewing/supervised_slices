defmodule SupervisedSlices.Analytics do
  @moduledoc "Fire-and-forget PostHog event capture for server-side events."

  defp config, do: Application.get_env(:supervised_slices, :posthog, [])

  @doc """
  Captures a PostHog event from the server side.
  No-ops silently when POSTHOG_API_KEY is not configured (dev/test).
  Always returns :ok so callers don't need to handle errors.
  """
  def capture(event, distinct_id, properties \\ %{}) do
    api_key = config()[:api_key]
    host = config()[:host] || "https://us.i.posthog.com"

    if api_key && distinct_id do
      Task.start(fn ->
        Req.post("#{host}/capture/",
          json: %{
            api_key: api_key,
            event: event,
            distinct_id: to_string(distinct_id),
            properties: properties
          },
          receive_timeout: 5_000
        )
      end)
    end

    :ok
  end
end
