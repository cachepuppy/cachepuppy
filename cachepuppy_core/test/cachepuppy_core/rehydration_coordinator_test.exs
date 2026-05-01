defmodule CachePuppyCore.RehydrationCoordinatorTest do
  use ExUnit.Case, async: false

  alias CachePuppyCore.Persistence.CacheRouter

  @registry CachePuppyCore.CacheShardRegistry
  @coord_key :rehydration_coordinator

  setup do
    :ok = CachePuppyCore.CacheShardSync.reset_horde_shards!()

    case Horde.Registry.lookup(@registry, @coord_key) do
      [{coord_pid, _}] ->
        :ok = :sys.suspend(coord_pid)

        on_exit(fn ->
          _ = :sys.resume(coord_pid)
        end)

      [] ->
        :ok
    end

    :ok
  end

  test "coordinator tick rehydrates first Horde shard still in :none" do
    storage_dir = CachePuppyCore.TestTmpDir.path("rehydration_coordinator_tick")
    old_storage = Application.get_env(:cachepuppy_core, :cache_storage_dir)
    old_tick = Application.get_env(:cachepuppy_core, :cache_rehydration_coordinator_tick_ms)

    Application.put_env(:cachepuppy_core, :cache_storage_dir, storage_dir)
    Application.put_env(:cachepuppy_core, :cache_rehydration_coordinator_tick_ms, 60_000)

    try do
      File.mkdir_p!(storage_dir)
      {:ok, pid} = CacheRouter.ensure_shard_started(0)

      assert :none == :sys.get_state(pid).rehydration_phase

      [{coord_pid, _}] = Horde.Registry.lookup(@registry, @coord_key)
      :ok = :sys.resume(coord_pid)
      send(coord_pid, :tick)

      wait_phase!(pid, :success, 200)
      assert :sys.get_state(pid).ready?
    after
      _ = CachePuppyCore.CacheShardSync.reset_horde_shards!()
      restore_env(:cache_storage_dir, old_storage)
      restore_env(:cache_rehydration_coordinator_tick_ms, old_tick)
    end
  end

  test "coordinator tick skips shards already :success" do
    storage_dir = CachePuppyCore.TestTmpDir.path("rehydration_coordinator_skip")
    old_storage = Application.get_env(:cachepuppy_core, :cache_storage_dir)
    old_tick = Application.get_env(:cachepuppy_core, :cache_rehydration_coordinator_tick_ms)

    Application.put_env(:cachepuppy_core, :cache_storage_dir, storage_dir)
    Application.put_env(:cachepuppy_core, :cache_rehydration_coordinator_tick_ms, 60_000)

    try do
      File.mkdir_p!(storage_dir)
      {:ok, pid} = CacheRouter.ensure_shard_started(0)
      :ok = CachePuppyCore.CacheShardRehydrate.rehydrate_and_wait_ready!(pid)

      assert {:ok, :skipped} = GenServer.call(pid, :rehydrate_sync)

      [{coord_pid, _}] = Horde.Registry.lookup(@registry, @coord_key)
      :ok = :sys.resume(coord_pid)
      send(coord_pid, :tick)

      assert {:ok, :skipped} = GenServer.call(pid, :rehydrate_sync)
    after
      _ = CachePuppyCore.CacheShardSync.reset_horde_shards!()
      restore_env(:cache_storage_dir, old_storage)
      restore_env(:cache_rehydration_coordinator_tick_ms, old_tick)
    end
  end

  defp wait_phase!(pid, phase, attempts)
  defp wait_phase!(_pid, phase, 0), do: flunk("shard did not reach phase #{inspect(phase)}")

  defp wait_phase!(pid, phase, attempts) do
    if :sys.get_state(pid).rehydration_phase == phase do
      :ok
    else
      receive do
      after
        20 -> wait_phase!(pid, phase, attempts - 1)
      end
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:cachepuppy_core, key)
  defp restore_env(key, value), do: Application.put_env(:cachepuppy_core, key, value)
end
