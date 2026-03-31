defmodule SupervisedSlices.Accounts.GuestSession do
  @moduledoc """
  A lightweight actor struct for unauthenticated (guest) users. Pass this as
  the `actor:` option when making Ash calls on behalf of a guest browsing an
  org's storefront. The `session_id` is a UUID generated and stored in the
  LiveView/browser session cookie.

  Policies on Cart and CartItem check `actor(:session_id)` to authorize
  guest access without requiring a user account.
  """
  defstruct [:session_id]
end
