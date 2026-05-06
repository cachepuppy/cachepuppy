defmodule CachePuppyCore.Persistence.CacheShardMaintenanceProcessTest do
  use CachePuppyCore.CachePersistenceCase, async: false

  alias CachePuppyCore.Persistence.CacheShardFlushProcess
  alias CachePuppyCore.Persistence.CacheShardMaintenanceProcess
  alias CachePuppyCore.Persistence.CacheUtils

  test "snapshot writes checkpoint with cutoff and prunes older WAL segments", %{
    storage_dir: storage_dir
  } do
    Application.put_env(:cachepuppy_core, :cache_wal_segment_max_bytes, 64)
    {:ok, flush} = start_supervised({CacheShardFlushProcess, [shard_id: 880]})

    {:ok, maint} =
      start_supervised({CacheShardMaintenanceProcess, [shard_id: 880, flush_pid: flush]})

    for idx <- 1..12 do
      :ok =
        CacheShardFlushProcess.enqueue(flush, {:set, "t", "k#{idx}", %{"v" => idx}, idx, nil})
    end

    Process.sleep(120)
    assert :ok = CacheShardMaintenanceProcess.snapshot(maint)

    {:ok, cp_bin} = File.read(CacheUtils.checkpoint_path(storage_dir, 880))
    cutoff = :erlang.binary_to_term(cp_bin)["snapshot_cutoff_seq"]
    assert is_integer(cutoff)
    assert cutoff > 1

    Enum.each(CacheUtils.wal_segments(storage_dir, 880), fn {seq, _, _} ->
      assert seq >= cutoff
    end)
  end

  test "checkpoint fallback uses seq 1 for malformed checkpoint", %{storage_dir: storage_dir} do
    shard_id = 884
    :ok = File.write(CacheUtils.checkpoint_path(storage_dir, shard_id), "bad")

    {:ok, flush} = start_supervised({CacheShardFlushProcess, [shard_id: shard_id]})

    {:ok, maint} =
      start_supervised({CacheShardMaintenanceProcess, [shard_id: shard_id, flush_pid: flush]})

    :ok = CacheShardFlushProcess.enqueue(flush, {:set, "t", "k", %{"v" => 1}, 1, nil})
    Process.sleep(60)
    assert {:ok, tid} = CacheShardMaintenanceProcess.load_from_disk(maint)
    assert [{{"t", "k"}, _}] = :ets.lookup(tid, {"t", "k"})
  end

  test "prune keeps seq equal to cutoff", %{storage_dir: storage_dir} do
    Application.put_env(:cachepuppy_core, :cache_wal_segment_max_bytes, 64)
    {:ok, flush} = start_supervised({CacheShardFlushProcess, [shard_id: 885]})

    {:ok, maint} =
      start_supervised({CacheShardMaintenanceProcess, [shard_id: 885, flush_pid: flush]})

    for i <- 1..20,
        do: :ok = CacheShardFlushProcess.enqueue(flush, {:set, "t", "k#{i}", i, i, nil})

    Process.sleep(120)
    assert :ok = CacheShardMaintenanceProcess.snapshot(maint)

    {:ok, cp_bin} = File.read(CacheUtils.checkpoint_path(storage_dir, 885))
    cutoff = :erlang.binary_to_term(cp_bin)["snapshot_cutoff_seq"]

    assert Enum.any?(CacheUtils.wal_segments(storage_dir, 885), fn {seq, _, _} ->
             seq == cutoff
           end)
  end

  test "load_from_disk replays set overwrite and delete ordering" do
    {:ok, flush} = start_supervised({CacheShardFlushProcess, [shard_id: 881]})

    {:ok, maint} =
      start_supervised({CacheShardMaintenanceProcess, [shard_id: 881, flush_pid: flush]})

    :ok = CacheShardFlushProcess.enqueue(flush, {:set, "t", "a", %{"v" => 1}, 10, nil})
    :ok = CacheShardFlushProcess.enqueue(flush, {:set, "t", "a", %{"v" => 2}, 11, nil})
    :ok = CacheShardFlushProcess.enqueue(flush, {:set, "t", "b", %{"v" => 9}, 12, nil})
    :ok = CacheShardFlushProcess.enqueue(flush, {:delete, "t", "b", 13})
    Process.sleep(100)

    assert {:ok, tid} = CacheShardMaintenanceProcess.load_from_disk(maint)
    assert [{{"t", "a"}, entry_a}] = :ets.lookup(tid, {"t", "a"})
    assert entry_a.value == %{"v" => 2}
    assert [] == :ets.lookup(tid, {"t", "b"})
  end

  test "replay respects recovery_max_segments cap", %{storage_dir: storage_dir} do
    shard_id = 886
    Application.put_env(:cachepuppy_core, :cache_recovery_max_segments, 1)

    wal1 = CacheUtils.wal_path(storage_dir, shard_id, 1)
    wal2 = CacheUtils.wal_path(storage_dir, shard_id, 2)

    :ok = File.write(wal1, encode_record({:set, "t", "k1", %{"v" => 1}, 1, nil}))
    :ok = File.write(wal2, encode_record({:set, "t", "k2", %{"v" => 2}, 2, nil}))

    {:ok, flush} = start_supervised({CacheShardFlushProcess, [shard_id: shard_id]})

    {:ok, maint} =
      start_supervised({CacheShardMaintenanceProcess, [shard_id: shard_id, flush_pid: flush]})

    assert {:ok, tid} = CacheShardMaintenanceProcess.load_from_disk(maint)

    assert [{{"t", "k1"}, _}] = :ets.lookup(tid, {"t", "k1"})
    assert [] == :ets.lookup(tid, {"t", "k2"})
  end

  test "load_from_disk truncates corrupt/incomplete WAL tail to valid bytes", %{
    storage_dir: storage_dir
  } do
    shard_id = 882
    wal_path = CacheUtils.wal_path(storage_dir, shard_id, 1)
    good = encode_record({:set, "t", "ok", %{"v" => 1}, 20, nil})
    bad_prefix = <<0, 0, 0, 20, 1, 2, 3>>
    :ok = File.write(wal_path, good <> bad_prefix)

    {:ok, flush} = start_supervised({CacheShardFlushProcess, [shard_id: shard_id]})

    {:ok, maint} =
      start_supervised({CacheShardMaintenanceProcess, [shard_id: shard_id, flush_pid: flush]})

    assert {:ok, tid} = CacheShardMaintenanceProcess.load_from_disk(maint)
    assert [{{"t", "ok"}, entry}] = :ets.lookup(tid, {"t", "ok"})
    assert entry.value == %{"v" => 1}
    {:ok, truncated} = File.read(wal_path)
    assert truncated == good
  end

  test "replay truncates when malformed term appears mid-stream", %{storage_dir: storage_dir} do
    shard_id = 887
    wal = CacheUtils.wal_path(storage_dir, shard_id, 1)
    good1 = encode_record({:set, "t", "k1", 1, 1, nil})
    bad = <<0, 0, 0, 4, 1, 2, 3, 4>>
    good2 = encode_record({:set, "t", "k2", 2, 2, nil})
    :ok = File.write(wal, good1 <> bad <> good2)

    {:ok, flush} = start_supervised({CacheShardFlushProcess, [shard_id: shard_id]})

    {:ok, maint} =
      start_supervised({CacheShardMaintenanceProcess, [shard_id: shard_id, flush_pid: flush]})

    assert {:ok, tid} = CacheShardMaintenanceProcess.load_from_disk(maint)
    assert [{{"t", "k1"}, _}] = :ets.lookup(tid, {"t", "k1"})
    assert [] == :ets.lookup(tid, {"t", "k2"})
  end

  test "repeated snapshot then load_from_disk cycles remain deterministic", %{
    storage_dir: storage_dir
  } do
    {:ok, flush} = start_supervised({CacheShardFlushProcess, [shard_id: 883]})

    {:ok, maint} =
      start_supervised({CacheShardMaintenanceProcess, [shard_id: 883, flush_pid: flush]})

    for cycle <- 1..5 do
      :ok =
        CacheShardFlushProcess.enqueue(
          flush,
          {:set, "loop", "k", %{"cycle" => cycle}, 100 + cycle, nil}
        )

      Process.sleep(50)
      assert :ok = CacheShardMaintenanceProcess.snapshot(maint)
      assert {:ok, tid} = CacheShardMaintenanceProcess.load_from_disk(maint)
      assert is_reference(tid)

      {:ok, cp_bin} = File.read(CacheUtils.checkpoint_path(storage_dir, 883))
      cp = :erlang.binary_to_term(cp_bin)
      assert is_integer(cp["snapshot_cutoff_seq"])
      assert cp["snapshot_cutoff_seq"] >= 1
    end
  end

  defp encode_record(term) do
    payload = :erlang.term_to_binary(term)
    <<byte_size(payload)::unsigned-integer-size(32), payload::binary>>
  end
end
