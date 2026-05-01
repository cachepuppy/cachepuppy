defmodule CachePuppyCore.RehydrationCoordinator do
  @moduledoc false

  # Registered locally on each node — not via Horde.Registry. A unique Horde key
  # would allow only one coordinator cluster-wide; starting one per node caused
  # naming-conflict exits and application shutdown in multi-node Docker.

  use GenServer
  require Logger

  alias CachePuppyCore.ClusterQuorumGuard
  alias CachePuppyCore.Persistence.CacheConfig

  @registry CachePuppyCore.CacheShardRegistry

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def child_spec(opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @impl true
  def init(_opts) do
    {:ok, schedule_tick(%{})}
  end

  @impl true
  def handle_info(:tick, state) do
    _ =
      if ClusterQuorumGuard.quorum_status().quorum_met do
        pick_and_rehydrate_one()
      else
        :ok
      end

    {:noreply, schedule_tick(state)}
  end

  defp schedule_tick(state) do
    _ = Process.send_after(self(), :tick, CacheConfig.rehydration_coordinator_tick_ms())
    state
  end

  defp pick_and_rehydrate_one do
    n = CacheConfig.shard_count()

    Enum.reduce_while(0..(n - 1), :ok, fn shard_id, _acc ->
      case Horde.Registry.lookup(@registry, shard_id) do
        [{pid, _}] ->
          case GenServer.call(pid, :rehydrate_sync, :infinity) do
            :ok ->
              {:halt, :ok}

            {:ok, :skipped} ->
              {:cont, :ok}

            {:error, reason} ->
              Logger.warning(
                "rehydration_coordinator rehydrate_failed shard_id=#{shard_id} reason=#{inspect(reason)}"
              )

              {:halt, :ok}
          end

        [] ->
          {:cont, :ok}
      end
    end)
  end
end
