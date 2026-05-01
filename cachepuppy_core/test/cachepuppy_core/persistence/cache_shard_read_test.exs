defmodule CachePuppyCore.Persistence.CacheShardReadTest do
  use ExUnit.Case, async: false

  alias CachePuppyCore.CacheShardRehydrate
  alias CachePuppyCore.Persistence.CacheShardProcess
  alias CachePuppyCore.Persistence.CacheShardRead

  test "fast_get returns rehydrating while shard metadata is not ready" do
    shard_id = 101
    table = :ets.new(:rehydrating_shard, [:set, :protected])
    CacheShardRead.publish_rehydrating(shard_id, table, 1)

    on_exit(fn ->
      CacheShardRead.clear(self())
    end)

    assert {:error, :rehydrating} = CacheShardRead.fast_get(shard_id, "users", "alpha")
  end

  test "fast_get returns value directly from ETS once ready" do
    shard_id = 102
    storage_dir = unique_storage_dir("fast_get_ready")

    with_cache_config(storage_dir, fn ->
      pid = start_supervised!({CacheShardProcess, shard_id: shard_id, name: nil})
      wait_until_ready(pid)

      assert {:ok, 42} = GenServer.call(pid, {:set, "users", "answer", 42})
      assert {:ok, 42} = CacheShardRead.fast_get(shard_id, "users", "answer")
      assert {:ok, nil} = CacheShardRead.fast_get(shard_id, "users", "missing")
    end)
  end

  test "fast_get returns shard_unavailable when no shard metadata exists" do
    assert {:error, :shard_unavailable} = CacheShardRead.fast_get(999_999, "users", "k")
  end

  defp with_cache_config(storage_dir, fun) do
    old_storage = Application.get_env(:cachepuppy_core, :cache_storage_dir)
    old_flush = Application.get_env(:cachepuppy_core, :cache_flush_interval_ms)

    Application.put_env(:cachepuppy_core, :cache_storage_dir, storage_dir)
    Application.put_env(:cachepuppy_core, :cache_flush_interval_ms, 30_000)

    try do
      fun.()
    after
      restore_env(:cache_storage_dir, old_storage)
      restore_env(:cache_flush_interval_ms, old_flush)
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:cachepuppy_core, key)
  defp restore_env(key, value), do: Application.put_env(:cachepuppy_core, key, value)

  defp unique_storage_dir(label) do
    CachePuppyCore.TestTmpDir.path("cache_shard_read_#{label}")
  end

  defp wait_until_ready(pid, attempts \\ 200) do
    CacheShardRehydrate.rehydrate_and_wait_ready!(pid, attempts: attempts)
  end
end
