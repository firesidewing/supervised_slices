defmodule SupervisedSlices.Accounts.GuestSession do
  @moduledoc """
  A lightweight actor struct for unauthenticated (guest) users. Pass this as
  the `actor:` option when making Ash calls on behalf of a guest browsing an
  org's storefront. The `session_id` is a UUID generated and stored in the
  LiveView/browser session cookie.

  Policies check `actor(:id)` uniformly for both guests and users.
  """
  defstruct [:id]
end
