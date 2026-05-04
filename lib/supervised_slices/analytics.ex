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

  @doc "Telemetry handler — called automatically on any LiveView crash."
  def handle_lv_exception(_event, _measurements, metadata, _config) do
    %{kind: kind, reason: reason, stacktrace: stacktrace} = metadata

    distinct_id =
      case get_in(metadata, [:socket, Access.key(:assigns), :current_user]) do
        %{id: uid} -> uid
        _ -> "server"
      end

    extra =
      %{}
      |> maybe_put("liveview", metadata[:socket] && to_string(metadata[:socket].view))
      |> maybe_put("event", metadata[:event])

    capture_exception(kind, reason, stacktrace, distinct_id: distinct_id, extra: extra)
  end

  @doc "Manually capture a server-side exception. Call from rescue blocks when needed."
  def capture_exception(kind, reason, stacktrace, opts \\ []) do
    distinct_id = Keyword.get(opts, :distinct_id, "server")
    extra = Keyword.get(opts, :extra, %{})

    {type, message} =
      case kind do
        :error when is_exception(reason) ->
          {to_string(reason.__struct__), Exception.message(reason)}

        _ ->
          {"#{kind}", inspect(reason)}
      end

    capture(
      "$exception",
      distinct_id,
      Map.merge(extra, %{
        "$exception_list" => [
          %{
            "type" => type,
            "value" => message,
            "stacktrace" => %{"frames" => Exception.format_stacktrace(stacktrace)}
          }
        ]
      })
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
