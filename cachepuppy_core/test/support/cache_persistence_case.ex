defmodule CachePuppyCore.CachePersistenceCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias CachePuppyCore.CacheShardSync

  using do
    quote do
      alias CachePuppyCore.Persistence.CacheRouter
      alias CachePuppyCore.Persistence.CacheShardRead
      alias CachePuppyCore.Persistence.CacheOwnerMeta
      alias CachePuppyCore.Persistence.CacheUtils
    end
  end

  setup _tags do
    uniq = System.unique_integer([:positive])
    storage_dir = CachePuppyCore.TestTmpDir.path("cache_persistence_#{uniq}")

    old_storage = Application.get_env(:cachepuppy_core, :cache_storage_dir)
    old_shards = Application.get_env(:cachepuppy_core, :cache_shard_count)
    old_flush = Application.get_env(:cachepuppy_core, :cache_flush_interval_ms)
    old_ttl_sweep = Application.get_env(:cachepuppy_core, :cache_ttl_sweep_interval_ms)
    old_wal_max = Application.get_env(:cachepuppy_core, :cache_wal_segment_max_bytes)
    old_snapshot_interval = Application.get_env(:cachepuppy_core, :cache_snapshot_interval_ms)
    old_snapshot_min = Application.get_env(:cachepuppy_core, :cache_snapshot_min_wal_bytes)

    Application.put_env(:cachepuppy_core, :cache_storage_dir, storage_dir)
    Application.put_env(:cachepuppy_core, :cache_shard_count, 16)
    Application.put_env(:cachepuppy_core, :cache_flush_interval_ms, 25)
    Application.put_env(:cachepuppy_core, :cache_ttl_sweep_interval_ms, 25)
    Application.put_env(:cachepuppy_core, :cache_wal_segment_max_bytes, 512)
    Application.put_env(:cachepuppy_core, :cache_snapshot_interval_ms, 600_000)
    Application.put_env(:cachepuppy_core, :cache_snapshot_min_wal_bytes, 1)

    :ok = CacheShardSync.reset_horde_shards!()
    _ = File.rm_rf(storage_dir)
    :ok = File.mkdir_p(storage_dir)

    on_exit(fn ->
      _ = CacheShardSync.reset_horde_shards!()
      restore(:cache_storage_dir, old_storage)
      restore(:cache_shard_count, old_shards)
      restore(:cache_flush_interval_ms, old_flush)
      restore(:cache_ttl_sweep_interval_ms, old_ttl_sweep)
      restore(:cache_wal_segment_max_bytes, old_wal_max)
      restore(:cache_snapshot_interval_ms, old_snapshot_interval)
      restore(:cache_snapshot_min_wal_bytes, old_snapshot_min)
      _ = File.rm_rf(storage_dir)
    end)

    {:ok, storage_dir: storage_dir}
  end

  defp restore(key, nil), do: Application.delete_env(:cachepuppy_core, key)
  defp restore(key, value), do: Application.put_env(:cachepuppy_core, key, value)
end
