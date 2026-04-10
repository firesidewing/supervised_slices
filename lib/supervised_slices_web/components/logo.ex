defmodule SupervisedSlicesWeb.Components.Logo do
  use Phoenix.Component

  @doc """
  Renders the Supervised Slices logo.
  """
  attr :class, :string, default: nil

  def logo(assigns) do
    ~H"""
    <div class={["flex items-center gap-3", @class]}>
      <div class="size-12 bg-gradient-to-tr from-primary to-primary-container rounded-2xl flex items-center justify-center -rotate-6 shadow-[0px_12px_32px_rgba(93,63,62,0.12)] ring-4 ring-primary/5">
        <span class="material-symbols-outlined text-on-primary !text-3xl font-black">local_pizza</span>
      </div>
      <div class="flex flex-col -gap-1">
        <span class="font-headline font-black text-2xl tracking-tight uppercase italic text-on-surface leading-none">
          Supervised<span class="text-primary">Slices</span>
        </span>
        <span class="font-body text-[10px] font-black tracking-[0.2em] uppercase text-on-surface-variant/40 ml-0.5">
          Artisanal Tech
        </span>
      </div>
    </div>
    """
  end
end
