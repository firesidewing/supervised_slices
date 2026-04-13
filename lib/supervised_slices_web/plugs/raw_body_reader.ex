defmodule SupervisedSlicesWeb.Plugs.RawBodyReader do
  @moduledoc """
  Caches the raw request body in `conn.private[:raw_body]` so the Stripe
  webhook controller can verify the Stripe-Signature header.

  Used as the `body_reader` option in `Plug.Parsers`.
  """

  require Logger

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        if should_cache?(conn) do
          Logger.info(
            "RawBodyReader: caching body for #{conn.request_path}, size=#{byte_size(body)}"
          )

          existing = Map.get(conn.private, :stripe_raw_body, [])
          conn = Plug.Conn.put_private(conn, :stripe_raw_body, [body | existing])
          {:ok, body, conn}
        else
          {:ok, body, conn}
        end

      {:more, body, conn} ->
        if should_cache?(conn) do
          Logger.info(
            "RawBodyReader: caching body chunk for #{conn.request_path}, size=#{byte_size(body)}"
          )

          existing = Map.get(conn.private, :stripe_raw_body, [])
          conn = Plug.Conn.put_private(conn, :stripe_raw_body, [body | existing])
          {:more, body, conn}
        else
          {:more, body, conn}
        end
    end
  end

  defp should_cache?(conn) do
    String.starts_with?(conn.request_path, "/webhooks/stripe")
  end
end
