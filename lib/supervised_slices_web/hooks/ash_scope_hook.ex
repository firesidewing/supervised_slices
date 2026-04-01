defmodule SupervisedSlicesWeb.AshScopeHook do
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, params, session, socket) do
    actor = socket.assigns[:current_user]

    org =
      socket.assigns[:org] ||
        load_org_from_params(params)

    scope = %SupervisedSlices.Scope{
      current_user: actor,
      current_tenant: org && org.id,
      guest_session_id: session["guest_session_id"]
    }

    {:cont,
     socket
     |> assign(:org, org)
     |> assign(:ash_scope, scope)}
  end

  defp load_org_from_params(%{"org_slug" => slug}) do
    SupervisedSlices.Orgs.Organization
    |> Ash.Query.for_read(:by_slug, %{slug: slug})
    |> Ash.read_one!()
  end

  defp load_org_from_params(_), do: nil
end
