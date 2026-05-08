defmodule SupervisedSlices.PromEx do
  use PromEx, otp_app: :supervised_slices

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix,
       router: SupervisedSlicesWeb.Router, endpoint: SupervisedSlicesWeb.Endpoint},
      {PromEx.Plugins.Ecto, otp_app: :supervised_slices, repo: SupervisedSlices.Repo},
      {PromEx.Plugins.Oban, otp_app: :supervised_slices}
    ]
  end
end
