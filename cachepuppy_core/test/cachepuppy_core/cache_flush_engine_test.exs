defmodule CachePuppyCore.CacheFlushEngineTest do
  use ExUnit.Case, async: false

  alias CachePuppyCore.Persistence.CacheFlushEngine
  alias CachePuppyCore.Persistence.CacheUtils

  test "start_link creates first WAL segment on cold start" do
    shard_id = 1
    storage_dir = unique_storage_dir("init_cold")

    with_cache_config(storage_dir, 1024, fn ->
      write_owner_meta(storage_dir, shard_id, 1)
      table = :ets.new(:engine_init_cold, [:set, :protected])
      pid = start_engine(shard_id, table, 1)
      state = :sys.get_state(pid)
      assert state.engine.current_seq == 1
      assert state.engine.current_wal_bytes == 0
      assert File.exists?(CacheUtils.wal_path(storage_dir, shard_id, 1))
    end)
  end

  test "start_link resumes latest WAL segment and size" do
    shard_id = 2
    storage_dir = unique_storage_dir("init_resume")

    with_cache_config(storage_dir, 1024, fn ->
      File.mkdir_p!(storage_dir)
      File.write!(CacheUtils.wal_path(storage_dir, shard_id, 1), "abc")
      File.write!(CacheUtils.wal_path(storage_dir, shard_id, 2), "abcdef")
      write_owner_meta(storage_dir, shard_id, 1)
      table = :ets.new(:engine_init_resume, [:set, :protected])
      pid = start_engine(shard_id, table, 1)

      state = :sys.get_state(pid)
      assert state.engine.current_seq == 2
      assert state.engine.current_wal_bytes == 6
    end)
  end

  test "persist_set appends WAL record when owner is valid" do
    shard_id = 3
    storage_dir = unique_storage_dir("persist_valid")

    with_cache_config(storage_dir, 1024, fn ->
      write_owner_meta(storage_dir, shard_id, 11)
      table = :ets.new(:engine_persist_valid, [:set, :protected])
      pid = start_engine(shard_id, table, 11)
      CacheFlushEngine.persist_set(pid, "users", "k1", "v1")
      state = :sys.get_state(pid)
      assert state.engine.current_wal_bytes > 0
      assert state.engine.pending_sync_bytes > 0
      assert File.stat!(CacheUtils.wal_path(storage_dir, shard_id, 1)).size > 0
    end)
  end

  test "persist_set is ignored when owner metadata is stale" do
    shard_id = 4
    storage_dir = unique_storage_dir("persist_stale")

    with_cache_config(storage_dir, 1024, fn ->
      write_owner_meta(storage_dir, shard_id, 11)
      table = :ets.new(:engine_persist_stale, [:set, :protected])
      pid = start_engine(shard_id, table, 11)

      File.write!(
        Path.join(storage_dir, "shard_#{shard_id}.meta"),
        :erlang.term_to_binary(%{
          "epoch" => 999,
          "owner_node" => "other@node",
          "rehydrating" => false,
          "updated_at_ms" => System.system_time(:millisecond)
        })
      )

      CacheFlushEngine.persist_set(pid, "users", "k1", "v1")
      _ = :sys.get_state(pid)
      assert File.stat!(CacheUtils.wal_path(storage_dir, shard_id, 1)).size == 0
    end)
  end

  test "flush tick syncs pending WAL bytes" do
    shard_id = 5
    storage_dir = unique_storage_dir("sync")

    with_cache_config(storage_dir, 1024, fn ->
      write_owner_meta(storage_dir, shard_id, 11)
      table = :ets.new(:engine_sync, [:set, :protected])
      pid = start_engine(shard_id, table, 11)

      CacheFlushEngine.persist_set(pid, "users", "k1", "v1")
      state_before = :sys.get_state(pid)
      assert state_before.engine.pending_sync_bytes > 0

      send(pid, :flush_tick)
      state_after = :sys.get_state(pid)
      assert state_after.engine.pending_sync_bytes == 0
    end)
  end

  test "flush tick rotates WAL when size threshold exceeded" do
    shard_id = 6
    storage_dir = unique_storage_dir("rotate")

    with_cache_config(storage_dir, 64, fn ->
      write_owner_meta(storage_dir, shard_id, 11)
      table = :ets.new(:engine_rotate, [:set, :protected])
      pid = start_engine(shard_id, table, 11)
      CacheFlushEngine.persist_set(pid, "users", "k1", String.duplicate("a", 80))
      send(pid, :flush_tick)
      state = :sys.get_state(pid)
      assert state.engine.current_seq == 2
      assert File.exists?(CacheUtils.wal_path(storage_dir, shard_id, 2))
    end)
  end

  test "flush tick writes snapshot and checkpoint when thresholds are met" do
    shard_id = 7
    storage_dir = unique_storage_dir("snapshot")

    with_cache_config(storage_dir, 1_048_576, fn ->
      write_owner_meta(storage_dir, shard_id, 11)
      table = :ets.new(:engine_snapshot, [:set, :protected])
      true = :ets.insert(table, {{"users", "name"}, "beamline"})

      pid =
        start_supervised!(
          {CacheFlushEngine,
           shard_id: shard_id,
           table: table,
           owner_epoch: 11,
           snapshot_interval_ms: 0,
           snapshot_min_wal_bytes: 1}
        )

      CacheFlushEngine.persist_set(pid, "users", "city", "blr")
      send(pid, :flush_tick)
      wait_until(fn ->
        File.exists?(CacheUtils.snapshot_path(storage_dir, shard_id)) and
          File.exists?(CacheUtils.checkpoint_path(storage_dir, shard_id))
      end)
    end)
  end

  test "snapshot finalization prunes older WAL segments" do
    shard_id = 8
    storage_dir = unique_storage_dir("prune")

    with_cache_config(storage_dir, 40, fn ->
      write_owner_meta(storage_dir, shard_id, 11)
      table = :ets.new(:engine_prune, [:set, :protected])

      pid =
        start_supervised!(
          {CacheFlushEngine,
           shard_id: shard_id,
           table: table,
           owner_epoch: 11,
           snapshot_interval_ms: 0,
           snapshot_min_wal_bytes: 1}
        )

      CacheFlushEngine.persist_set(pid, "users", "k1", String.duplicate("a", 80))
      send(pid, :flush_tick)
      CacheFlushEngine.persist_set(pid, "users", "k2", String.duplicate("b", 80))
      send(pid, :flush_tick)

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.engine.current_seq >= 3
      end)

      wait_until(fn ->
        not File.exists?(CacheUtils.wal_path(storage_dir, shard_id, 1))
      end)
    end)
  end

  test "engine process terminates cleanly" do
    shard_id = 9
    storage_dir = unique_storage_dir("terminate")

    with_cache_config(storage_dir, 1_048_576, fn ->
      write_owner_meta(storage_dir, shard_id, 11)
      table = :ets.new(:engine_terminate, [:set, :protected])
      pid = start_engine(shard_id, table, 11)
      ref = Process.monitor(pid)
      :ok = GenServer.stop(pid, :normal)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end)
  end

  test "does not persist writes while metadata is rehydrating" do
    shard_id = 10
    storage_dir = unique_storage_dir("rehydrating_block")

    with_cache_config(storage_dir, 1024, fn ->
      File.mkdir_p!(storage_dir)
      File.write!(
        Path.join(storage_dir, "shard_#{shard_id}.meta"),
        :erlang.term_to_binary(%{
          "epoch" => 1,
          "owner_node" => to_string(node()),
          "rehydrating" => true,
          "updated_at_ms" => System.system_time(:millisecond)
        })
      )

      table = :ets.new(:engine_rehydrating_block, [:set, :protected])
      pid = start_engine(shard_id, table, 1)
      CacheFlushEngine.persist_set(pid, "users", "k1", "v1")
      _ = :sys.get_state(pid)

      assert File.stat!(CacheUtils.wal_path(storage_dir, shard_id, 1)).size == 0
    end)
  end

  defp with_cache_config(storage_dir, wal_segment_max_bytes, fun) do
    old_storage = Application.get_env(:cachepuppy_core, :cache_storage_dir)
    old_wal_bytes = Application.get_env(:cachepuppy_core, :cache_wal_segment_max_bytes)

    Application.put_env(:cachepuppy_core, :cache_storage_dir, storage_dir)
    Application.put_env(:cachepuppy_core, :cache_wal_segment_max_bytes, wal_segment_max_bytes)

    try do
      fun.()
    after
      restore_env(:cache_storage_dir, old_storage)
      restore_env(:cache_wal_segment_max_bytes, old_wal_bytes)
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

  defp start_engine(shard_id, table, owner_epoch) do
    start_supervised!(
      {CacheFlushEngine,
       shard_id: shard_id,
       table: table,
       owner_epoch: owner_epoch,
       snapshot_interval_ms: 60_000,
       snapshot_min_wal_bytes: 1_000}
    )
  end

  defp write_owner_meta(storage_dir, shard_id, epoch) do
    File.mkdir_p!(storage_dir)

    File.write!(
      Path.join(storage_dir, "shard_#{shard_id}.meta"),
      :erlang.term_to_binary(%{
        "epoch" => epoch,
        "owner_node" => to_string(node()),
        "rehydrating" => false,
        "updated_at_ms" => System.system_time(:millisecond)
      })
    )
  end

  defp wait_until(fun, attempts \\ 100)
  defp wait_until(_fun, 0), do: flunk("condition not met")

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      receive do
      after
        10 -> wait_until(fun, attempts - 1)
      end
    end
  end
end
