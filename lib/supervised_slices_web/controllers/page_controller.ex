defmodule SupervisedSlicesWeb.PageController do
  use SupervisedSlicesWeb, :controller

  def home(conn, _params) do
    user = conn.assigns[:current_user]
    render(conn, :home, kitchen_org: get_kitchen_org(user))
  end

  defp get_kitchen_org(nil), do: nil

  defp get_kitchen_org(user) do
    user.id
    |> SupervisedSlices.Orgs.Membership.get_kitchen_membership(authorize?: false)
    |> case do
      {:ok, [membership | _]} -> membership.organization
      _ -> nil
    end
  end
end
