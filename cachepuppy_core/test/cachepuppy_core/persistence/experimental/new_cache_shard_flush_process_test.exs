defmodule CachePuppyCore.Persistence.Experimental.NewCacheShardFlushProcessTest do
  use CachePuppyCore.ExperimentalPersistenceCase, async: false

  alias CachePuppyCore.Persistence.Experimental.NewCacheShardFlushProcess
  alias CachePuppyCore.Persistence.Experimental.NewCacheUtils

  test "timer flush persists WAL and resets in-memory batch", %{storage_dir: storage_dir} do
    {:ok, pid} = start_supervised({NewCacheShardFlushProcess, [shard_id: 777]})

    :ok = NewCacheShardFlushProcess.enqueue(pid, {:set, "users", "a", %{"x" => 1}, 1, nil})

    wait_for(fn ->
      case NewCacheUtils.wal_segments(storage_dir, 777) do
        [{_seq, _path, size}] when size > 0 -> true
        _ -> false
      end
    end)

    state = :sys.get_state(pid)
    assert state.batch_count == 0
    assert state.batch_buf == []
  end

  test "rotation creates multiple WAL segments at byte boundary", %{storage_dir: storage_dir} do
    Application.put_env(:cachepuppy_core, :cache_wal_segment_max_bytes, 64)

    {:ok, pid} = start_supervised({NewCacheShardFlushProcess, [shard_id: 778]})

    for idx <- 1..15 do
      :ok =
        NewCacheShardFlushProcess.enqueue(
          pid,
          {:set, "users", "k#{idx}", %{"payload" => String.duplicate("x", 24)}, idx, nil}
        )
    end

    wait_for(fn -> length(NewCacheUtils.wal_segments(storage_dir, 778)) >= 2 end)

    segs = NewCacheUtils.wal_segments(storage_dir, 778)
    assert length(segs) >= 2

    seqs = Enum.map(segs, fn {seq, _p, _s} -> seq end)
    assert seqs == Enum.sort(seqs)
    assert Enum.uniq(seqs) == seqs
  end

  test "prepare_snapshot seals non-empty segment and returns included seq", %{
    storage_dir: storage_dir
  } do
    {:ok, pid} = start_supervised({NewCacheShardFlushProcess, [shard_id: 779]})
    :ok = NewCacheShardFlushProcess.enqueue(pid, {:set, "users", "a", %{"x" => 1}, 2, nil})
    wait_for(fn -> NewCacheUtils.wal_segments(storage_dir, 779) != [] end)

    assert {:ok, included_seq} = NewCacheShardFlushProcess.prepare_snapshot(pid)
    assert is_integer(included_seq)
    assert included_seq >= 1

    state = :sys.get_state(pid)
    assert state.paused?
    assert state.current_wal_fd == nil
  end

  test "prepare_snapshot drops empty tail segment branch", %{storage_dir: storage_dir} do
    Application.put_env(:cachepuppy_core, :cache_wal_segment_max_bytes, 64)

    {:ok, pid} = start_supervised({NewCacheShardFlushProcess, [shard_id: 780]})

    for idx <- 1..12 do
      :ok =
        NewCacheShardFlushProcess.enqueue(
          pid,
          {:set, "users", "k#{idx}", %{"payload" => String.duplicate("y", 24)}, idx, nil}
        )
    end

    wait_for(fn -> length(NewCacheUtils.wal_segments(storage_dir, 780)) >= 2 end)

    assert {:ok, included_seq} = NewCacheShardFlushProcess.prepare_snapshot(pid)

    segs = NewCacheUtils.wal_segments(storage_dir, 780)
    max_existing_seq = segs |> Enum.map(fn {seq, _, _} -> seq end) |> Enum.max(fn -> 1 end)

    assert included_seq <= max_existing_seq
    assert included_seq >= 1
  end

  test "pause queue accumulates and drains on resume", %{storage_dir: storage_dir} do
    {:ok, pid} = start_supervised({NewCacheShardFlushProcess, [shard_id: 781]})

    assert {:ok, included_seq} = NewCacheShardFlushProcess.prepare_snapshot(pid)
    state_paused = :sys.get_state(pid)
    assert state_paused.paused?

    :ok = NewCacheShardFlushProcess.enqueue(pid, {:set, "t", "a", %{"v" => 1}, 10, nil})
    :ok = NewCacheShardFlushProcess.enqueue(pid, {:set, "t", "b", %{"v" => 2}, 11, nil})

    state_q = :sys.get_state(pid)
    assert :queue.len(state_q.pause_q) == 2

    assert :ok = NewCacheShardFlushProcess.resume_after_snapshot(pid, max(1, included_seq + 1))

    wait_for(fn ->
      NewCacheUtils.wal_segments(storage_dir, 781)
      |> Enum.any?(fn {_seq, _path, size} -> size > 0 end)
    end)

    state_after = :sys.get_state(pid)
    assert state_after.paused? == false
    assert :queue.is_empty(state_after.pause_q)
  end

  test "close_for_rehydration and open_after_rehydration restore writable lifecycle", %{
    storage_dir: storage_dir
  } do
    {:ok, pid} = start_supervised({NewCacheShardFlushProcess, [shard_id: 782]})

    :ok = NewCacheShardFlushProcess.enqueue(pid, {:set, "t", "before", %{"v" => 1}, 20, nil})
    wait_for(fn -> NewCacheUtils.wal_segments(storage_dir, 782) != [] end)

    assert :ok = NewCacheShardFlushProcess.close_for_rehydration(pid)

    closed = :sys.get_state(pid)
    assert closed.paused?
    assert closed.current_wal_fd == nil

    assert :ok = NewCacheShardFlushProcess.open_after_rehydration(pid)

    reopened = :sys.get_state(pid)
    assert reopened.paused? == false
    assert reopened.current_wal_fd != nil

    :ok = NewCacheShardFlushProcess.enqueue(pid, {:set, "t", "after", %{"v" => 2}, 21, nil})

    wait_for(fn ->
      NewCacheUtils.wal_segments(storage_dir, 782)
      |> Enum.any?(fn {_seq, _path, size} -> size > 0 end)
    end)
  end

  test "open_after_rehydration returns error when storage dir disappears", %{
    storage_dir: storage_dir
  } do
    {:ok, pid} = start_supervised({NewCacheShardFlushProcess, [shard_id: 783]})
    assert :ok = NewCacheShardFlushProcess.close_for_rehydration(pid)

    _ = File.rm_rf(storage_dir)
    assert {:error, :enoent} = NewCacheShardFlushProcess.open_after_rehydration(pid)
  end

  defp wait_for(fun, attempts \\ 60)

  defp wait_for(_fun, 0), do: flunk("timed out waiting for condition")

  defp wait_for(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      wait_for(fun, attempts - 1)
    end
  end
end
