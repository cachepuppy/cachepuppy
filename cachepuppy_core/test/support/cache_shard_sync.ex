defmodule CachePuppyCore.CacheShardSync do
  @moduledoc false

  import ExUnit.Assertions

  alias CachePuppyCore.CacheShardRehydrate
  alias CachePuppyCore.Persistence.Experimental.NewCacheRouter
  alias CachePuppyCore.Persistence.Experimental.NewCacheShardRead

  @max_shard_scan 127

  @doc """
  Terminates every Horde-managed `CacheShardProcess` (and linked TTL sweeper) so a test
  that changes `cache_storage_dir` does not inherit stale processes from another test.
  """
  @spec reset_horde_shards!() :: :ok
  def reset_horde_shards! do
    sup = CachePuppyCore.CacheShardSupervisor
    reg = CachePuppyCore.CacheShardRegistry

    for sid <- 0..@max_shard_scan do
      case Horde.Registry.lookup(reg, sid) do
        [{pid, _}] ->
          _ = Horde.DynamicSupervisor.terminate_child(sup, pid)

        [] ->
          :ok
      end
    end

    :ok
  end

  @doc """
  Starts the shard for `table` + `key` (if needed), runs synchronous rehydration on the
  shard pid (does not wait on `RehydrationCoordinator` ticks), then blocks until:

  * `CacheShardProcess` is `ready?: true` and `owner_valid?: true`
  * `NewCacheShardRead.shard_meta/1` reports `ready?: true` for the same owner pid

  This matches what HTTP and `CacheRouter` need before `{:error, :rehydrating}` disappears.
  """
  @spec sync!(String.t(), String.t()) :: :ok
  def sync!(table, key) when is_binary(table) and is_binary(key) do
    {:ok, shard_id} = NewCacheRouter.shard_id_for_entry(table, key)
    {:ok, pid} = NewCacheRouter.ensure_shard_started(shard_id)
    :ok = CacheShardRehydrate.rehydrate_and_wait_ready!(pid)
    assert_process_ready!(pid)
    assert_public_meta_ready!(shard_id, pid)
  end

  defp assert_process_ready!(pid, attempts \\ 500)

  defp assert_process_ready!(_pid, 0),
    do: flunk("cache shard process did not become ready with valid ownership")

  defp assert_process_ready!(pid, attempts) do
    state = :sys.get_state(pid)

    if state.ready? and state.owner_valid? do
      :ok
    else
      receive do
      after
        5 -> assert_process_ready!(pid, attempts - 1)
      end
    end
  end

  defp assert_public_meta_ready!(shard_id, owner_pid, attempts \\ 200)

  defp assert_public_meta_ready!(shard_id, _owner_pid, 0),
    do: flunk("CacheShardRead meta did not publish ready for shard #{shard_id}")

  defp assert_public_meta_ready!(shard_id, owner_pid, attempts) do
    case NewCacheShardRead.shard_meta(shard_id) do
      %{ready?: true, owner_pid: ^owner_pid} ->
        :ok

      _ ->
        receive do
        after
          5 -> assert_public_meta_ready!(shard_id, owner_pid, attempts - 1)
        end
    end
  end
end
