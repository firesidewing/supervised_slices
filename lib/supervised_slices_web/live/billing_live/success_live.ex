defmodule SupervisedSlicesWeb.BillingLive.Success do
  use SupervisedSlicesWeb, :live_view

  on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    org = socket.assigns.org

    if is_nil(org) do
      {:ok, redirect(socket, to: ~p"/")}
    else
      {:ok, assign(socket, :org, org)}
    end
  end
end
