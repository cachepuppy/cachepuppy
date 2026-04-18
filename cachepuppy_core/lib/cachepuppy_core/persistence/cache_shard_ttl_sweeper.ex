defmodule CachePuppyCore.Persistence.CacheShardTtlSweeper do
  @moduledoc false

  use GenServer

  alias CachePuppyCore.Persistence.CacheConfig
  alias CachePuppyCore.Persistence.CacheEntry
  alias CachePuppyCore.Persistence.CacheShardRead

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)
    owner = Keyword.fetch!(opts, :owner)
    GenServer.start_link(__MODULE__, %{shard_id: shard_id, owner: owner})
  end

  @spec run_once(pid()) :: :ok
  def run_once(pid) when is_pid(pid), do: GenServer.call(pid, :run_once)

  @impl true
  def init(%{shard_id: shard_id} = state) do
    _ = schedule_tick(shard_id)
    {:ok, state}
  end

  @impl true
  def handle_info({:tick, shard_id}, state) do
    sweep(shard_id, state.owner)
    _ = schedule_tick(shard_id)
    {:noreply, state}
  end

  @impl true
  def handle_call(:run_once, _from, %{shard_id: sid, owner: owner} = state) do
    sweep(sid, owner)
    {:reply, :ok, state}
  end

  defp schedule_tick(shard_id) do
    Process.send_after(self(), {:tick, shard_id}, CacheConfig.ttl_sweep_interval_ms())
  end

  defp sweep(shard_id, owner_pid) do
    case CacheShardRead.shard_meta(shard_id) do
      %{ready?: true, table: tid, owner_pid: ^owner_pid} ->
        now = System.system_time(:millisecond)

        keys =
          :ets.foldl(
            fn
              {{table, key}, %CacheEntry{expires_at_ms: exp}}, acc
              when is_integer(exp) and exp <= now and is_binary(table) and is_binary(key) ->
                [{table, key} | acc]

              _, acc ->
                acc
            end,
            [],
            tid
          )

        Enum.each(keys, fn {t, k} ->
          _ = GenServer.call(owner_pid, {:delete, t, k})
        end)

      _ ->
        :ok
    end
  end
end
