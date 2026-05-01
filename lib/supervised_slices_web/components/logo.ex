defmodule SupervisedSlicesWeb.Components.Logo do
  use Phoenix.Component

  @doc """
  Renders the Supervised Slices logo.
  """
  attr :class, :string, default: nil

  def logo(assigns) do
    ~H"""
    <div class={["flex items-center gap-2", @class]}>
      <picture>
        <source srcset="/images/chit.webp" type="image/webp" />
        <img src="/images/chit.png" alt="Chitline" class="h-10 w-auto mix-blend-multiply" />
      </picture>
    </div>
    """
  end
end
