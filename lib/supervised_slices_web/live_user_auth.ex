defmodule SupervisedSlicesWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  import Phoenix.Component
  use SupervisedSlicesWeb, :verified_routes

  # This is used for nested liveviews to fetch the current user.
  # To use, place the following at the top of that liveview:
  # on_mount {SupervisedSlicesWeb.LiveUserAuth, :current_user}
  def on_mount(:current_user, _params, session, socket) do
    {:cont, AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session)}
  end

  def on_mount(:live_user_optional, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:live_user_required, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  @doc """
  Requires an authenticated user AND an active (or trialing) subscription on
  the org that was loaded by AshScopeHook from the URL's :org_slug param.
  Unauthenticated users go to sign-in; authenticated users without an active
  subscription go to the billing setup page for their org.
  """
  def on_mount(:live_user_and_subscription_required, _params, _session, socket) do
    user = socket.assigns[:current_user]
    org = socket.assigns[:org]

    cond do
      is_nil(user) ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}

      is_nil(org) ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}

      org.subscription_status in [:active, :trialing] ->
        {:cont, socket}

      true ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/billing/setup/#{org.slug}")}
    end
  end
end
