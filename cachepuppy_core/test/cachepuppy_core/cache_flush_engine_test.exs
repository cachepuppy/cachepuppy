defmodule CachePuppyCore.CacheFlushEngineTest do
  use ExUnit.Case, async: false

  alias CachePuppyCore.Persistence.CacheFlushEngine
  alias CachePuppyCore.Persistence.CacheUtils

  test "init creates first WAL segment on cold start" do
    shard_id = 1
    storage_dir = unique_storage_dir("init_cold")

    with_cache_config(storage_dir, 1024, 0, fn ->
      {:ok, engine} = CacheFlushEngine.init(shard_id: shard_id)
      assert engine.current_seq == 1
      assert engine.current_wal_bytes == 0
      assert File.exists?(CacheUtils.wal_path(storage_dir, shard_id, 1))
      _ = CacheFlushEngine.close(engine)
    end)
  end

  test "init resumes latest WAL segment and size" do
    shard_id = 2
    storage_dir = unique_storage_dir("init_resume")

    with_cache_config(storage_dir, 1024, 0, fn ->
      File.mkdir_p!(storage_dir)
      File.write!(CacheUtils.wal_path(storage_dir, shard_id, 1), "abc")
      File.write!(CacheUtils.wal_path(storage_dir, shard_id, 2), "abcdef")

      {:ok, engine} = CacheFlushEngine.init(shard_id: shard_id)
      assert engine.current_seq == 2
      assert engine.current_wal_bytes == 6
      _ = CacheFlushEngine.close(engine)
    end)
  end

  test "close returns engine with nil file descriptor" do
    shard_id = 3
    storage_dir = unique_storage_dir("close")

    with_cache_config(storage_dir, 1024, 0, fn ->
      {:ok, engine} = CacheFlushEngine.init(shard_id: shard_id)
      closed = CacheFlushEngine.close(engine)
      assert closed.current_wal_fd == nil
    end)
  end

  test "append_set increases WAL and pending counters" do
    shard_id = 4
    storage_dir = unique_storage_dir("append")

    with_cache_config(storage_dir, 1024, 0, fn ->
      {:ok, engine} = CacheFlushEngine.init(shard_id: shard_id)
      assert {:ok, engine} = CacheFlushEngine.append_set(engine, "users", "k1", "v1")
      assert engine.current_wal_bytes > 0
      assert engine.pending_sync_bytes > 0
      assert engine.wal_bytes_since_snapshot > 0
      _ = CacheFlushEngine.close(engine)
    end)
  end

  test "maybe_sync is no-op when no pending bytes" do
    shard_id = 5
    storage_dir = unique_storage_dir("sync_noop")

    with_cache_config(storage_dir, 1024, 0, fn ->
      {:ok, engine} = CacheFlushEngine.init(shard_id: shard_id)
      assert {:ok, synced} = CacheFlushEngine.maybe_sync(engine)
      assert synced.pending_sync_bytes == 0
      _ = CacheFlushEngine.close(synced)
    end)
  end

  test "maybe_sync flushes pending bytes when interval elapsed" do
    shard_id = 6
    storage_dir = unique_storage_dir("sync_flush")

    with_cache_config(storage_dir, 1024, 0, fn ->
      {:ok, engine} = CacheFlushEngine.init(shard_id: shard_id)
      {:ok, engine} = CacheFlushEngine.append_set(engine, "users", "k1", "v1")
      assert {:ok, synced} = CacheFlushEngine.maybe_sync(engine)
      assert synced.pending_sync_bytes == 0
      _ = CacheFlushEngine.close(synced)
    end)
  end

  test "maybe_sync does not flush before sync interval" do
    shard_id = 7
    storage_dir = unique_storage_dir("sync_interval")

    with_cache_config(storage_dir, 1024, 60_000, fn ->
      {:ok, engine} = CacheFlushEngine.init(shard_id: shard_id)
      {:ok, engine} = CacheFlushEngine.append_set(engine, "users", "k1", "v1")
      assert {:ok, same_engine} = CacheFlushEngine.maybe_sync(engine)
      assert same_engine.pending_sync_bytes > 0
      _ = CacheFlushEngine.close(same_engine)
    end)
  end

  test "maybe_rotate is no-op below configured segment size" do
    shard_id = 8
    storage_dir = unique_storage_dir("rotate_noop")

    with_cache_config(storage_dir, 1_048_576, 0, fn ->
      {:ok, engine} = CacheFlushEngine.init(shard_id: shard_id)
      {:ok, engine} = CacheFlushEngine.append_set(engine, "users", "k1", "v1")
      assert {:ok, same_engine} = CacheFlushEngine.maybe_rotate(engine)
      assert same_engine.current_seq == 1
      _ = CacheFlushEngine.close(same_engine)
    end)
  end

  test "maybe_rotate rotates to next segment when threshold exceeded" do
    shard_id = 9
    storage_dir = unique_storage_dir("rotate")

    with_cache_config(storage_dir, 64, 0, fn ->
      {:ok, engine} = CacheFlushEngine.init(shard_id: shard_id)

      {:ok, engine} =
        CacheFlushEngine.append_set(engine, "users", "k1", String.duplicate("a", 80))

      assert {:ok, rotated} = CacheFlushEngine.maybe_rotate(engine)
      assert rotated.current_seq == 2
      assert rotated.current_wal_bytes == 0
      assert File.exists?(CacheUtils.wal_path(storage_dir, shard_id, 2))
      _ = CacheFlushEngine.close(rotated)
    end)
  end

  test "snapshot decision requires wal bytes and interval" do
    engine = %CacheFlushEngine{
      shard_id: 10,
      current_seq: 1,
      current_wal_fd: nil,
      current_wal_bytes: 0,
      pending_sync_bytes: 0,
      wal_bytes_since_snapshot: 100,
      last_sync_at_ms: System.system_time(:millisecond),
      last_snapshot_at_ms: System.system_time(:millisecond) - 10_000
    }

    assert CacheFlushEngine.should_snapshot?(engine, 1_000, 50)
    refute CacheFlushEngine.should_snapshot?(engine, 60_000, 50)
    refute CacheFlushEngine.should_snapshot?(%{engine | wal_bytes_since_snapshot: 10}, 1_000, 50)
  end

  test "mark_snapshot_started updates timestamp and cutoff sequence mirrors current seq" do
    before = System.system_time(:millisecond) - 100

    engine = %CacheFlushEngine{
      shard_id: 11,
      current_seq: 4,
      current_wal_fd: nil,
      current_wal_bytes: 0,
      pending_sync_bytes: 0,
      wal_bytes_since_snapshot: 0,
      last_sync_at_ms: before,
      last_snapshot_at_ms: before
    }

    updated = CacheFlushEngine.mark_snapshot_started(engine)
    assert updated.last_snapshot_at_ms >= before
    assert CacheFlushEngine.snapshot_cutoff_seq(updated) == 4
  end

  test "finalize_snapshot writes checkpoint, prunes older segments, and resets WAL snapshot bytes" do
    shard_id = 12
    storage_dir = unique_storage_dir("finalize")

    with_cache_config(storage_dir, 1024, 0, fn ->
      File.mkdir_p!(storage_dir)
      File.write!(CacheUtils.wal_path(storage_dir, shard_id, 1), "old")
      File.write!(CacheUtils.wal_path(storage_dir, shard_id, 2), "new")

      {:ok, engine} = CacheFlushEngine.init(shard_id: shard_id)
      engine = %{engine | wal_bytes_since_snapshot: 123}
      {:ok, finalized} = CacheFlushEngine.finalize_snapshot(engine, 2)

      assert finalized.wal_bytes_since_snapshot == 0
      assert File.exists?(CacheUtils.checkpoint_path(storage_dir, shard_id))
      refute File.exists?(CacheUtils.wal_path(storage_dir, shard_id, 1))
      assert File.exists?(CacheUtils.wal_path(storage_dir, shard_id, 2))
      _ = CacheFlushEngine.close(finalized)
    end)
  end

  test "write_snapshot persists ETS table to snapshot path" do
    shard_id = 13
    storage_dir = unique_storage_dir("write_snapshot")

    with_cache_config(storage_dir, 1024, 0, fn ->
      File.mkdir_p!(storage_dir)
      table = :ets.new(:flush_snapshot_seed, [:set, :protected])
      true = :ets.insert(table, {{"users", "name"}, "beamline"})
      assert :ok = CacheFlushEngine.write_snapshot(table, shard_id)
      :ets.delete(table)

      assert File.exists?(CacheUtils.snapshot_path(storage_dir, shard_id))

      assert {:ok, restored} =
               :ets.file2tab(String.to_charlist(CacheUtils.snapshot_path(storage_dir, shard_id)))

      assert [{{"users", "name"}, "beamline"}] = :ets.lookup(restored, {"users", "name"})
      :ets.delete(restored)
    end)
  end

  defp with_cache_config(storage_dir, wal_segment_max_bytes, wal_sync_interval_ms, fun) do
    old_storage = Application.get_env(:cachepuppy_core, :cache_storage_dir)
    old_wal_bytes = Application.get_env(:cachepuppy_core, :cache_wal_segment_max_bytes)
    old_sync = Application.get_env(:cachepuppy_core, :cache_wal_sync_interval_ms)

    Application.put_env(:cachepuppy_core, :cache_storage_dir, storage_dir)
    Application.put_env(:cachepuppy_core, :cache_wal_segment_max_bytes, wal_segment_max_bytes)
    Application.put_env(:cachepuppy_core, :cache_wal_sync_interval_ms, wal_sync_interval_ms)

    try do
      fun.()
    after
      restore_env(:cache_storage_dir, old_storage)
      restore_env(:cache_wal_segment_max_bytes, old_wal_bytes)
      restore_env(:cache_wal_sync_interval_ms, old_sync)
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:cachepuppy_core, key)
  defp restore_env(key, value), do: Application.put_env(:cachepuppy_core, key, value)

  defp unique_storage_dir(label) do
    Path.join(
      System.tmp_dir!(),
      "cache_flush_engine_#{label}_#{System.unique_integer([:positive])}"
    )
  end
end
