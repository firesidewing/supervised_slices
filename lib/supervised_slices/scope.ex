defmodule SupervisedSlices.Scope do
  defstruct [:current_user, :current_tenant, :guest_session_id]

  defimpl Ash.Scope.ToOpts do
    def get_actor(%{current_user: user}), do: {:ok, user}

    def get_tenant(%{current_tenant: tenant}), do: {:ok, tenant}

    def get_context(%{guest_session_id: guest_session_id}) do
      {:ok, %{guest_session_id: guest_session_id}}
    end

    def get_tracer(_), do: :error
    def get_authorize?(_), do: :error
  end
end
