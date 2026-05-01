defmodule SupervisedSlicesWeb.Components.Logo do
  use Phoenix.Component

  @doc """
  Renders the Supervised Slices logo.
  """
  attr :class, :string, default: nil

  def logo(assigns) do
    ~H"""
    <div class={["flex items-center gap-2", @class]}>
      <img src="/images/chit-2.png" alt="Chitline" class="h-10 w-auto" />
    </div>
    """
  end
end
