defmodule SupervisedSlicesWeb.Plugs.RawBodyReader do
  @moduledoc """
  Caches the raw request body in `conn.private[:raw_body]` so the Stripe
  webhook controller can verify the Stripe-Signature header.

  Used as the `body_reader` option in `Plug.Parsers`.
  """

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    existing = Map.get(conn.private, :raw_body, [])
    conn = Plug.Conn.put_private(conn, :raw_body, [body | existing])
    {:ok, body, conn}
  end
end
