defmodule SupervisedSlices.OrgPresence do
  @moduledoc """
  Phoenix.Presence for tracking which customers are currently browsing an org's
  storefront. The admin dashboard subscribes to presence diffs to show a live
  visitor count.

  Usage in a customer LiveView:
    def mount(_params, _session, socket) do
      org_id = socket.assigns.org.id
      session_id = get_session(socket, :session_id)
      SupervisedSlices.OrgPresence.track_visitor(self(), org_id, session_id)
      SupervisedSlices.OrgPresence.subscribe(org_id)
      ...
    end

  Usage in the admin LiveView:
    def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
      visitors = SupervisedSlices.OrgPresence.list_visitors(socket.assigns.org.id)
      {:noreply, assign(socket, :visitor_count, map_size(visitors))}
    end
  """

  use Phoenix.Presence,
    otp_app: :supervised_slices,
    pubsub_server: SupervisedSlices.PubSub

  @doc "Track a visitor in the given org's presence group."
  def track_visitor(pid, org_id, session_id, meta \\ %{}) do
    track(pid, presence_topic(org_id), session_id, meta)
  end

  @doc "List all visitors currently present on an org's storefront."
  def list_visitors(org_id) do
    list(presence_topic(org_id))
  end

  @doc "Subscribe to presence diffs for an org (use in admin LiveView mount)."
  def subscribe(org_id) do
    Phoenix.PubSub.subscribe(SupervisedSlices.PubSub, presence_topic(org_id))
  end

  defp presence_topic(org_id), do: "presence:org:#{org_id}"
end
