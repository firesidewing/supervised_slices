defmodule SupervisedSlicesWeb.Plugs.GuestSession do
  @moduledoc """
  Ensures every browser request has a `guest_session_id` in the session cookie.
  This UUID is used as the session_id for guest shopping carts, allowing
  unauthenticated users to add items without signing in.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, "guest_session_id") do
      conn
    else
      put_session(conn, "guest_session_id", Ash.UUIDv7.generate())
    end
  end
end
