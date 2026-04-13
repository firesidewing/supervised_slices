defmodule SupervisedSlicesWeb.AuthComponents.RegisterExtra do
  use Phoenix.Component
  import SupervisedSlicesWeb.CoreComponents

  def render(assigns) do
    ~H"""
    <.input
      field={@form[:organization_name]}
      label="Organization Name"
      placeholder="Enter your organization name"
      required
    />
    """
  end
end
