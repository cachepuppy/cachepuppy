defmodule CachePuppyCore.Persistence.CacheFlushEngineTest do
  use ExUnit.Case, async: false

  alias CachePuppyCore.Persistence.CacheShardProcess
  alias CachePuppyCore.Persistence.CacheFlushEngine
  alias CachePuppyCore.Persistence.CacheUtils

  test "shard creates first WAL segment on cold start" do
    shard_id = 1
    storage_dir = unique_storage_dir("init_cold")

    with_cache_config(storage_dir, 1024, fn ->
      write_owner_meta(storage_dir, shard_id, 1)
      pid = start_shard(shard_id)
      wait_until_ready(pid)
      state = :sys.get_state(pid)
      assert state.flush.current_seq == 1
      assert state.flush.current_wal_bytes == 0
      assert File.exists?(CacheUtils.wal_path(storage_dir, shard_id, 1))
    end)
  end

  test "shard resumes latest WAL segment and size" do
    shard_id = 2
    storage_dir = unique_storage_dir("init_resume")

    with_cache_config(storage_dir, 1024, fn ->
      File.mkdir_p!(storage_dir)
      File.write!(CacheUtils.wal_path(storage_dir, shard_id, 1), "abc")
      File.write!(CacheUtils.wal_path(storage_dir, shard_id, 2), "abcdef")
      write_owner_meta(storage_dir, shard_id, 1)
      pid = start_shard(shard_id)
      wait_until_ready(pid)

      state = :sys.get_state(pid)
      assert state.flush.current_seq == 2
      assert state.flush.current_wal_bytes == 6
    end)
  end

  test "set appends WAL record when owner is valid" do
    shard_id = 3
    storage_dir = unique_storage_dir("persist_valid")

    with_cache_config(storage_dir, 1024, fn ->
      write_owner_meta(storage_dir, shard_id, 11)
      pid = start_shard(shard_id)
      wait_until_ready(pid)
      assert {:ok, "v1"} = GenServer.call(pid, {:set, "users", "k1", "v1"})
      state = :sys.get_state(pid)
      assert state.flush.current_wal_bytes > 0
      assert state.flush.pending_sync_bytes > 0
      assert File.stat!(CacheUtils.wal_path(storage_dir, shard_id, 1)).size > 0
    end)
  end

  test "persist_set returns stale_owner when owner metadata does not match epoch" do
    shard_id = 4
    storage_dir = unique_storage_dir("persist_stale")

    with_cache_config(storage_dir, 1024, fn ->
      write_owner_meta(storage_dir, shard_id, 11)
      {:ok, flush} = flush_open(shard_id)

      File.write!(
        Path.join(storage_dir, "shard_#{shard_id}.meta"),
        :erlang.term_to_binary(%{
          "epoch" => 999,
          "owner_node" => "other@node",
          "rehydrating" => false,
          "updated_at_ms" => System.system_time(:millisecond)
        })
      )

      assert {:error, :stale_owner} = CacheFlushEngine.persist_set(flush, "users", "k1", "v1")
      _ = CacheFlushEngine.close(flush)
      assert File.stat!(CacheUtils.wal_path(storage_dir, shard_id, 1)).size == 0
    end)
  end

  test "flush tick syncs pending WAL bytes" do
    shard_id = 5
    storage_dir = unique_storage_dir("sync")

    with_cache_config(storage_dir, 1024, fn ->
      write_owner_meta(storage_dir, shard_id, 11)
      pid = start_shard(shard_id)
      wait_until_ready(pid)

      assert {:ok, "v1"} = GenServer.call(pid, {:set, "users", "k1", "v1"})
      state_before = :sys.get_state(pid)
      assert state_before.flush.pending_sync_bytes > 0

      send(pid, :flush_tick)
      state_after = :sys.get_state(pid)
      assert state_after.flush.pending_sync_bytes == 0
    end)
  end

  test "flush tick rotates WAL when size threshold exceeded" do
    shard_id = 6
    storage_dir = unique_storage_dir("rotate")

    with_cache_config(storage_dir, 64, fn ->
      write_owner_meta(storage_dir, shard_id, 11)
      pid = start_shard(shard_id)
      wait_until_ready(pid)

      assert {:ok, _} = GenServer.call(pid, {:set, "users", "k1", String.duplicate("a", 80)})
      send(pid, :flush_tick)
      state = :sys.get_state(pid)
      assert state.flush.current_seq == 2
      assert File.exists?(CacheUtils.wal_path(storage_dir, shard_id, 2))
    end)
  end

  test "flush tick writes snapshot and checkpoint when thresholds are met" do
    shard_id = 7
    storage_dir = unique_storage_dir("snapshot")

    with_cache_config(storage_dir, 1_048_576, fn ->
      with_snapshot_thresholds(0, 1, fn ->
        write_owner_meta(storage_dir, shard_id, 11)
        pid = start_shard(shard_id)
        wait_until_ready(pid)

        assert {:ok, "blr"} = GenServer.call(pid, {:set, "users", "city", "blr"})
        send(pid, :flush_tick)

        wait_until(fn ->
          File.exists?(CacheUtils.snapshot_path(storage_dir, shard_id)) and
            File.exists?(CacheUtils.checkpoint_path(storage_dir, shard_id))
        end)
      end)
    end)
  end

  test "snapshot finalization prunes older WAL segments" do
    shard_id = 8
    storage_dir = unique_storage_dir("prune")

    with_cache_config(storage_dir, 40, fn ->
      with_snapshot_thresholds(0, 1, fn ->
        write_owner_meta(storage_dir, shard_id, 11)
        pid = start_shard(shard_id)
        wait_until_ready(pid)

        assert {:ok, _} = GenServer.call(pid, {:set, "users", "k1", String.duplicate("a", 80)})
        send(pid, :flush_tick)
        assert {:ok, _} = GenServer.call(pid, {:set, "users", "k2", String.duplicate("b", 80)})
        send(pid, :flush_tick)

        wait_until(fn ->
          state = :sys.get_state(pid)
          state.flush.current_seq >= 3
        end)

        wait_until(fn ->
          not File.exists?(CacheUtils.wal_path(storage_dir, shard_id, 1))
        end)
      end)
    end)
  end

  test "shard process terminates cleanly" do
    shard_id = 9
    storage_dir = unique_storage_dir("terminate")

    with_cache_config(storage_dir, 1_048_576, fn ->
      write_owner_meta(storage_dir, shard_id, 11)
      pid = start_shard(shard_id)
      wait_until_ready(pid)
      ref = Process.monitor(pid)
      :ok = GenServer.stop(pid, :normal)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end)
  end

  test "persist_set returns stale_owner while shard metadata marks rehydrating" do
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

      {:ok, flush} = flush_open(shard_id, 1)
      assert {:error, :stale_owner} = CacheFlushEngine.persist_set(flush, "users", "k1", "v1")
      _ = CacheFlushEngine.close(flush)

      assert File.stat!(CacheUtils.wal_path(storage_dir, shard_id, 1)).size == 0
    end)
  end

  test "snapshot materializes from WAL only" do
    shard_id = 13
    storage_dir = unique_storage_dir("wal_only_snapshot")

    with_cache_config(storage_dir, 1_048_576, fn ->
      with_snapshot_thresholds(0, 1, fn ->
        write_owner_meta(storage_dir, shard_id, 11)
        pid = start_shard(shard_id)
        wait_until_ready(pid)

        assert {:ok, "from_wal"} = GenServer.call(pid, {:set, "users", "real", "from_wal"})
        send(pid, :flush_tick)

        wait_until(fn -> File.exists?(CacheUtils.snapshot_path(storage_dir, shard_id)) end)

        snap = :ets.file2tab(String.to_charlist(CacheUtils.snapshot_path(storage_dir, shard_id)))
        assert {:ok, tid} = snap
        assert [{{"users", "real"}, "from_wal"}] == :ets.lookup(tid, {"users", "real"})
        :ets.delete(tid)
      end)
    end)
  end

  test "snapshot creation is blocked while quorum snapshot fence is active but WAL appends continue" do
    shard_id = 11
    storage_dir = unique_storage_dir("snapshot_blocked_start")

    with_cache_config(storage_dir, 1_048_576, fn ->
      with_snapshot_thresholds(0, 1, fn ->
        write_owner_meta(storage_dir, shard_id, 11)
        set_snapshot_blocked(true)

        pid = start_shard(shard_id)
        wait_until_ready(pid)

        assert {:ok, "blr"} = GenServer.call(pid, {:set, "users", "city", "blr"})
        send(pid, :flush_tick)
        _ = :sys.get_state(pid)

        assert File.stat!(CacheUtils.wal_path(storage_dir, shard_id, 1)).size > 0
        refute File.exists?(CacheUtils.snapshot_path(storage_dir, shard_id))
        refute File.exists?(CacheUtils.checkpoint_path(storage_dir, shard_id))
      end)
    end)
  end

  test "snapshot finalize and prune are blocked while quorum snapshot fence is active" do
    shard_id = 12
    storage_dir = unique_storage_dir("snapshot_blocked_finalize")
    ref = make_ref()

    with_cache_config(storage_dir, 1_048_576, fn ->
      write_owner_meta(storage_dir, shard_id, 11)
      pid = start_shard(shard_id)
      wait_until_ready(pid)

      File.write!(CacheUtils.wal_path(storage_dir, shard_id, 1), "old-wal-segment")

      :sys.replace_state(pid, fn state ->
        %{state | flush: %{state.flush | snapshot_task_ref: ref}}
      end)

      set_snapshot_blocked(true)
      send(pid, {ref, {:snapshot_done, :ok, 2}})
      _ = :sys.get_state(pid)

      assert File.exists?(CacheUtils.wal_path(storage_dir, shard_id, 1))
      refute File.exists?(CacheUtils.checkpoint_path(storage_dir, shard_id))
    end)
  end

  defp flush_open(shard_id, owner_epoch \\ 11) do
    CacheFlushEngine.open(shard_id, owner_epoch)
  end

  defp with_snapshot_thresholds(interval_ms, min_wal_bytes, fun) do
    old_i = Application.get_env(:cachepuppy_core, :cache_snapshot_interval_ms)
    old_b = Application.get_env(:cachepuppy_core, :cache_snapshot_min_wal_bytes)

    Application.put_env(:cachepuppy_core, :cache_snapshot_interval_ms, interval_ms)
    Application.put_env(:cachepuppy_core, :cache_snapshot_min_wal_bytes, min_wal_bytes)

    try do
      fun.()
    after
      restore_env(:cache_snapshot_interval_ms, old_i)
      restore_env(:cache_snapshot_min_wal_bytes, old_b)
    end
  end

  defp with_cache_config(storage_dir, wal_segment_max_bytes, fun) do
    old_storage = Application.get_env(:cachepuppy_core, :cache_storage_dir)
    old_wal_bytes = Application.get_env(:cachepuppy_core, :cache_wal_segment_max_bytes)

    Application.put_env(:cachepuppy_core, :cache_storage_dir, storage_dir)
    Application.put_env(:cachepuppy_core, :cache_wal_segment_max_bytes, wal_segment_max_bytes)

    try do
      fun.()
    after
      set_snapshot_blocked(false)
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

  defp start_shard(shard_id) do
    start_supervised!({CacheShardProcess, shard_id: shard_id, name: nil})
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

  defp wait_until_ready(pid, attempts \\ 200)
  defp wait_until_ready(_pid, 0), do: flunk("shard did not become ready in time")

  defp wait_until_ready(pid, attempts) do
    state = :sys.get_state(pid)

    if state.ready? do
      :ok
    else
      receive do
      after
        10 -> wait_until_ready(pid, attempts - 1)
      end
    end
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

  defp set_snapshot_blocked(value) do
    :persistent_term.put({CachePuppyCore.ClusterQuorumGuard, :snapshot_blocked}, value)
  end
end
