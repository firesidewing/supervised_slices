defmodule SupervisedSlices.DbConnectionReady do
  @moduledoc false

  @max_attempts 20
  @delay_ms 500

  @doc """
  Blocks until the database accepts a query. Used before starting Oban on cold boot.
  """
  @spec wait() :: :ok
  def wait, do: wait_for_repo()

  defp wait_for_repo(attempt \\ 1)

  defp wait_for_repo(attempt) when attempt > @max_attempts do
    raise "database not reachable after #{@max_attempts} attempts"
  end

  defp wait_for_repo(attempt) do
    case SupervisedSlices.Repo.query("SELECT 1", [], timeout: 15_000) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        require Logger

        Logger.warning(
          "database not ready (attempt #{attempt}/#{@max_attempts}): #{inspect(reason)}"
        )

        Process.sleep(@delay_ms)
        wait_for_repo(attempt + 1)
    end
  end
end
