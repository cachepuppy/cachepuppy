defmodule CachePuppyCore.Persistence.Experimental.NewCacheShardMaintenanceProcessTest do
  use CachePuppyCore.ExperimentalPersistenceCase, async: false

  alias CachePuppyCore.Persistence.Experimental.NewCacheShardFlushProcess
  alias CachePuppyCore.Persistence.Experimental.NewCacheShardMaintenanceProcess
  alias CachePuppyCore.Persistence.Experimental.NewCacheUtils

  test "snapshot writes checkpoint with cutoff and prunes older WAL segments", %{
    storage_dir: storage_dir
  } do
    Application.put_env(:cachepuppy_core, :cache_wal_segment_max_bytes, 64)

    {:ok, flush} = start_supervised({NewCacheShardFlushProcess, [shard_id: 880]})

    {:ok, maint} =
      start_supervised({NewCacheShardMaintenanceProcess, [shard_id: 880, flush_pid: flush]})

    for idx <- 1..12 do
      :ok =
        NewCacheShardFlushProcess.enqueue(flush, {:set, "t", "k#{idx}", %{"v" => idx}, idx, nil})
    end

    Process.sleep(120)

    before = NewCacheUtils.wal_segments(storage_dir, 880)
    assert length(before) >= 2

    assert :ok = NewCacheShardMaintenanceProcess.snapshot(maint)

    cp_path = NewCacheUtils.checkpoint_path(storage_dir, 880)
    assert File.exists?(cp_path)

    {:ok, cp_bin} = File.read(cp_path)
    cp = :erlang.binary_to_term(cp_bin)
    cutoff = cp["snapshot_cutoff_seq"]
    assert is_integer(cutoff)
    assert cutoff > 1

    after_segments = NewCacheUtils.wal_segments(storage_dir, 880)
    assert after_segments != []

    Enum.each(after_segments, fn {seq, _path, _size} ->
      assert seq >= cutoff
    end)
  end

  test "load_from_disk replays set overwrite and delete ordering", %{storage_dir: storage_dir} do
    {:ok, flush} = start_supervised({NewCacheShardFlushProcess, [shard_id: 881]})

    {:ok, maint} =
      start_supervised({NewCacheShardMaintenanceProcess, [shard_id: 881, flush_pid: flush]})

    :ok = NewCacheShardFlushProcess.enqueue(flush, {:set, "t", "a", %{"v" => 1}, 10, nil})
    :ok = NewCacheShardFlushProcess.enqueue(flush, {:set, "t", "a", %{"v" => 2}, 11, nil})
    :ok = NewCacheShardFlushProcess.enqueue(flush, {:set, "t", "b", %{"v" => 9}, 12, nil})
    :ok = NewCacheShardFlushProcess.enqueue(flush, {:delete, "t", "b", 13})
    Process.sleep(100)

    assert {:ok, tid} = NewCacheShardMaintenanceProcess.load_from_disk(maint)

    assert [{{"t", "a"}, entry_a}] = :ets.lookup(tid, {"t", "a"})
    assert entry_a.value == %{"v" => 2}
    assert [] == :ets.lookup(tid, {"t", "b"})

    assert NewCacheUtils.wal_segments(storage_dir, 881) != []
  end

  test "load_from_disk truncates corrupt/incomplete WAL tail to valid bytes", %{
    storage_dir: storage_dir
  } do
    shard_id = 882
    wal_path = NewCacheUtils.wal_path(storage_dir, shard_id, 1)

    good = encode_record({:set, "t", "ok", %{"v" => 1}, 20, nil})
    bad_prefix = <<0, 0, 0, 20, 1, 2, 3>>
    :ok = File.write(wal_path, good <> bad_prefix)

    {:ok, flush} = start_supervised({NewCacheShardFlushProcess, [shard_id: shard_id]})

    {:ok, maint} =
      start_supervised({NewCacheShardMaintenanceProcess, [shard_id: shard_id, flush_pid: flush]})

    assert {:ok, tid} = NewCacheShardMaintenanceProcess.load_from_disk(maint)

    assert [{{"t", "ok"}, entry}] = :ets.lookup(tid, {"t", "ok"})
    assert entry.value == %{"v" => 1}

    {:ok, truncated} = File.read(wal_path)
    assert truncated == good
  end

  test "repeated snapshot then load_from_disk cycles remain deterministic", %{
    storage_dir: storage_dir
  } do
    {:ok, flush} = start_supervised({NewCacheShardFlushProcess, [shard_id: 883]})

    {:ok, maint} =
      start_supervised({NewCacheShardMaintenanceProcess, [shard_id: 883, flush_pid: flush]})

    for cycle <- 1..5 do
      :ok =
        NewCacheShardFlushProcess.enqueue(
          flush,
          {:set, "loop", "k", %{"cycle" => cycle}, 100 + cycle, nil}
        )

      Process.sleep(50)
      assert :ok = NewCacheShardMaintenanceProcess.snapshot(maint)
      assert {:ok, tid} = NewCacheShardMaintenanceProcess.load_from_disk(maint)
      assert is_reference(tid)

      cp_path = NewCacheUtils.checkpoint_path(storage_dir, 883)
      assert File.exists?(cp_path)
      {:ok, cp_bin} = File.read(cp_path)
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
