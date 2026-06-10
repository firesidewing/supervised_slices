defmodule SupervisedSlices.DeferredServices do
  @moduledoc false
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    send(self(), :start)
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:start, state) do
    Task.start(fn -> start_oban_when_ready() end)
    {:noreply, state}
  end

  defp start_oban_when_ready do
    :ok = SupervisedSlices.DbConnectionReady.wait()

    oban_config =
      AshOban.config(
        Application.fetch_env!(:supervised_slices, :ash_domains),
        Application.fetch_env!(:supervised_slices, Oban)
      )

    case Supervisor.start_link([{Oban, oban_config}],
           strategy: :one_for_one,
           name: SupervisedSlices.ObanSupervisor
         ) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.error("failed to start Oban: #{inspect(reason)}")
    end
  end
end
