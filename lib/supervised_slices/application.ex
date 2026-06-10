defmodule SupervisedSlices.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SupervisedSlicesWeb.Telemetry,
      SupervisedSlices.Repo,
      {DNSCluster, query: Application.get_env(:supervised_slices, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SupervisedSlices.PubSub},
      SupervisedSlices.OrgPresence,
      SupervisedSlicesWeb.Endpoint,
      SupervisedSlices.DeferredServices,
      {AshAuthentication.Supervisor, [otp_app: :supervised_slices]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SupervisedSlices.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SupervisedSlicesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
