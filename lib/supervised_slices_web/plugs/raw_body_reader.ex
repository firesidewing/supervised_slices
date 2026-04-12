defmodule SupervisedSlicesWeb.Plugs.RawBodyReader do
  @moduledoc """
  Caches the raw request body in `conn.private[:raw_body]` so the Stripe
  webhook controller can verify the Stripe-Signature header.

  Used as the `body_reader` option in `Plug.Parsers`.
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        if should_cache?(conn) do
          existing = Map.get(conn.private, :raw_body, [])
          conn = Plug.Conn.put_private(conn, :raw_body, [body | existing])
          {:ok, body, conn}
        else
          {:ok, body, conn}
        end

      {:more, body, conn} ->
        if should_cache?(conn) do
          existing = Map.get(conn.private, :raw_body, [])
          conn = Plug.Conn.put_private(conn, :raw_body, [body | existing])
          {:more, body, conn}
        else
          {:more, body, conn}
        end
    end
  end

  defp should_cache?(conn) do
    match?(["webhooks", "stripe"], conn.path_info)
  end
end
