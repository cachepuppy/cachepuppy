defmodule CachePuppyCore.Persistence.CacheShardProcessTest do
  use CachePuppyCore.CachePersistenceCase, async: false

  alias CachePuppyCore.Persistence.CacheOwnerMeta
  alias CachePuppyCore.Persistence.CacheShardProcess
  alias CachePuppyCore.Persistence.CacheShardRead

  test "startup rehydrate remains stable across repeated boots" do
    Enum.each(1..20, fn offset ->
      shard_id = 10_000 + offset
      {:ok, pid} = start_supervised({CacheShardProcess, [shard_id: shard_id, name: nil]})
      assert_shard_ready!(pid)
      assert Process.alive?(pid)
    end)
  end

  test "rehydrate_sync is idempotent and swapped table is owned by shard" do
    {:ok, pid} = start_supervised({CacheShardProcess, [shard_id: 20_001, name: nil]})
    assert_shard_ready!(pid)
    assert :ok = GenServer.call(pid, :rehydrate_sync)
    assert :ok = GenServer.call(pid, :rehydrate_sync)

    state = :sys.get_state(pid)
    assert state.ready?
    assert state.owner_valid?
    assert :ets.info(state.table, :owner) == pid
  end

  test "readiness gate rejects writes while rehydrating" do
    {:ok, pid} = start_supervised({CacheShardProcess, [shard_id: 20_002, name: nil]})
    assert_shard_ready!(pid)

    :sys.replace_state(pid, fn st -> %{st | ready?: false} end)
    assert {:error, :rehydrating} = GenServer.call(pid, {:set, "t", "k", 1, []})
    assert {:error, :rehydrating} = GenServer.call(pid, {:delete, "t", "k"})
    assert {:error, :rehydrating} = GenServer.call(pid, {:update, "t", "k", %{"x" => 1}, []})
  end

  test "owner invalidation rejects mutations and snapshot", %{storage_dir: storage_dir} do
    shard_id = 20_003
    {:ok, pid} = start_supervised({CacheShardProcess, [shard_id: shard_id, name: nil]})
    assert_shard_ready!(pid)

    state = :sys.get_state(pid)
    _new_epoch = CacheOwnerMeta.claim_ownership(storage_dir, shard_id, to_string(node()))

    send(pid, :owner_check_tick)
    Process.sleep(10)

    state_after = :sys.get_state(pid)
    refute state_after.owner_valid?

    assert {:error, :stale_owner} = GenServer.call(pid, {:set, "t", "k", 1, []})
    assert {:error, :stale_owner} = GenServer.call(pid, {:delete, "t", "k"})
    assert {:error, :stale_owner} = GenServer.call(pid, {:update, "t", "k", %{"x" => 1}, []})
    assert {:error, :stale_owner} = GenServer.call(pid, :snapshot)

    assert state_after.table == :sys.get_state(pid).table
    assert state.owner_epoch == state_after.owner_epoch
  end

  test "mutation contract coverage for ttl, patching, not_found and delete idempotence" do
    {:ok, pid} = start_supervised({CacheShardProcess, [shard_id: 20_004, name: nil]})
    assert_shard_ready!(pid)

    assert {:error, :invalid_ttl} = GenServer.call(pid, {:set, "t", "k", 1, [ttl_ms: -1]})
    assert {:error, :invalid_patch} = GenServer.call(pid, {:update, "t", "k", 1, []})
    assert {:error, :not_found} = GenServer.call(pid, {:update, "t", "missing", %{"x" => 1}, []})
    assert {:ok, false} = GenServer.call(pid, {:delete, "t", "missing"})

    assert {:ok, 10} = GenServer.call(pid, {:set, "t", "scalar", 10, []})

    assert {:error, :value_not_mergeable} =
             GenServer.call(pid, {:update, "t", "scalar", %{"x" => 1}, []})
  end

  test "ttl max boundary accepts max and rejects max plus one" do
    {:ok, pid} = start_supervised({CacheShardProcess, [shard_id: 20_007, name: nil]})
    assert_shard_ready!(pid)

    max = CachePuppyCore.Persistence.CacheConfig.ttl_ms_max()
    assert {:ok, 1} = GenServer.call(pid, {:set, "t", "max", 1, [ttl_ms: max]})
    assert {:error, :invalid_ttl} = GenServer.call(pid, {:set, "t", "over", 1, [ttl_ms: max + 1]})
  end

  test "update carries ttl forward when ttl_ms omitted" do
    {:ok, pid} = start_supervised({CacheShardProcess, [shard_id: 20_005, name: nil]})
    assert_shard_ready!(pid)

    assert {:ok, %{"a" => 1}} =
             GenServer.call(pid, {:set, "t", "ttl", %{"a" => 1}, [ttl_ms: 300]})

    :ok = Process.sleep(10)

    assert {:ok, %{"a" => 1, "b" => 2}} =
             GenServer.call(pid, {:update, "t", "ttl", %{"b" => 2}, []})

    state = :sys.get_state(pid)
    [{_, entry}] = :ets.lookup(state.table, {"t", "ttl"})

    assert is_integer(entry.expires_at_ms)
    assert entry.expires_at_ms > System.system_time(:millisecond)
  end

  test "update on expired entry returns not_found and does not revive" do
    {:ok, pid} = start_supervised({CacheShardProcess, [shard_id: 20_008, name: nil]})
    assert_shard_ready!(pid)
    assert {:ok, %{"a" => 1}} = GenServer.call(pid, {:set, "t", "exp", %{"a" => 1}, [ttl_ms: 1]})
    Process.sleep(5)
    assert {:error, :not_found} = GenServer.call(pid, {:update, "t", "exp", %{"b" => 2}, []})
  end

  test "owner validity stays stale after foreign epoch takes ownership", %{
    storage_dir: storage_dir
  } do
    shard_id = 20_009
    {:ok, pid} = start_supervised({CacheShardProcess, [shard_id: shard_id, name: nil]})
    assert_shard_ready!(pid)

    _ = CacheOwnerMeta.claim_ownership(storage_dir, shard_id, to_string(node()))
    send(pid, :owner_check_tick)
    Process.sleep(10)
    refute :sys.get_state(pid).owner_valid?

    send(pid, :owner_check_tick)
    Process.sleep(10)
    refute :sys.get_state(pid).owner_valid?
  end

  test "snapshot succeeds when owner valid" do
    {:ok, pid} = start_supervised({CacheShardProcess, [shard_id: 20_006, name: nil]})
    assert_shard_ready!(pid)

    assert {:ok, %{"v" => 1}} = GenServer.call(pid, {:set, "snap", "k", %{"v" => 1}, []})
    assert :ok = GenServer.call(pid, :snapshot)
  end

  test "periodic snapshot creates checkpoint and prunes older wal segments", %{storage_dir: storage_dir} do
    old_interval = Application.get_env(:cachepuppy_core, :cache_snapshot_interval_ms)
    old_wal_max = Application.get_env(:cachepuppy_core, :cache_wal_segment_max_bytes)
    old_snapshot_min = Application.get_env(:cachepuppy_core, :cache_snapshot_min_wal_bytes)

    Application.put_env(:cachepuppy_core, :cache_snapshot_interval_ms, 30)
    Application.put_env(:cachepuppy_core, :cache_wal_segment_max_bytes, 64)
    Application.put_env(:cachepuppy_core, :cache_snapshot_min_wal_bytes, 1)

    on_exit(fn ->
      restore(:cache_snapshot_interval_ms, old_interval)
      restore(:cache_wal_segment_max_bytes, old_wal_max)
      restore(:cache_snapshot_min_wal_bytes, old_snapshot_min)
    end)

    shard_id = 20_011
    {:ok, pid} = start_supervised({CacheShardProcess, [shard_id: shard_id, name: nil]})
    assert_shard_ready!(pid)

    for idx <- 1..20 do
      assert {:ok, %{"v" => ^idx}} =
               GenServer.call(pid, {:set, "snap", "k#{idx}", %{"v" => idx}, []})
    end

    snapshot_path = CacheUtils.snapshot_path(storage_dir, shard_id)
    checkpoint_path = CacheUtils.checkpoint_path(storage_dir, shard_id)

    assert_eventually(fn ->
      File.exists?(snapshot_path) and File.exists?(checkpoint_path)
    end)

    {:ok, cp_bin} = File.read(checkpoint_path)
    cutoff = :erlang.binary_to_term(cp_bin)["snapshot_cutoff_seq"]
    assert is_integer(cutoff)
    assert cutoff > 1

    Enum.each(CacheUtils.wal_segments(storage_dir, shard_id), fn {seq, _path, _size} ->
      assert seq >= cutoff
    end)
  end

  test "periodic snapshot skips when wal bytes are below threshold", %{storage_dir: storage_dir} do
    old_interval = Application.get_env(:cachepuppy_core, :cache_snapshot_interval_ms)
    old_snapshot_min = Application.get_env(:cachepuppy_core, :cache_snapshot_min_wal_bytes)

    Application.put_env(:cachepuppy_core, :cache_snapshot_interval_ms, 30)
    Application.put_env(:cachepuppy_core, :cache_snapshot_min_wal_bytes, 1_000_000)

    on_exit(fn ->
      restore(:cache_snapshot_interval_ms, old_interval)
      restore(:cache_snapshot_min_wal_bytes, old_snapshot_min)
    end)

    shard_id = 20_013
    {:ok, pid} = start_supervised({CacheShardProcess, [shard_id: shard_id, name: nil]})
    assert_shard_ready!(pid)

    assert {:ok, %{"v" => 1}} = GenServer.call(pid, {:set, "t", "k", %{"v" => 1}, []})
    Process.sleep(220)
    refute File.exists?(CacheUtils.snapshot_path(storage_dir, shard_id))
  end

  test "periodic snapshot tick does not run when owner is stale", %{storage_dir: storage_dir} do
    old_interval = Application.get_env(:cachepuppy_core, :cache_snapshot_interval_ms)
    old_snapshot_min = Application.get_env(:cachepuppy_core, :cache_snapshot_min_wal_bytes)
    Application.put_env(:cachepuppy_core, :cache_snapshot_interval_ms, 150)
    Application.put_env(:cachepuppy_core, :cache_snapshot_min_wal_bytes, 1)

    on_exit(fn ->
      restore(:cache_snapshot_interval_ms, old_interval)
      restore(:cache_snapshot_min_wal_bytes, old_snapshot_min)
    end)

    shard_id = 20_012
    {:ok, pid} = start_supervised({CacheShardProcess, [shard_id: shard_id, name: nil]})
    assert_shard_ready!(pid)

    _ = CacheOwnerMeta.claim_ownership(storage_dir, shard_id, to_string(node()))
    send(pid, :owner_check_tick)
    Process.sleep(10)
    refute :sys.get_state(pid).owner_valid?

    Process.sleep(220)
    refute File.exists?(CacheUtils.snapshot_path(storage_dir, shard_id))
  end

  test "termination clears only metadata owned by process" do
    tid = :ets.new(__MODULE__, [:set, :protected])
    :ok = CacheShardRead.publish_ready(98_001, tid, 1)

    {:ok, pid} = start_supervised({CacheShardProcess, [shard_id: 20_010, name: nil]})
    assert_shard_ready!(pid)
    sid = :sys.get_state(pid).shard_id

    GenServer.stop(pid)
    assert :undefined == CacheShardRead.shard_meta(sid)
    assert CacheShardRead.shard_meta(98_001) != :undefined
  end

  defp assert_shard_ready!(pid, attempts \\ 200)
  defp assert_shard_ready!(_pid, 0), do: flunk("shard did not become ready")

  defp assert_shard_ready!(pid, attempts) do
    state = :sys.get_state(pid)

    cond do
      state.ready? and state.owner_valid? ->
        assert %{ready?: true, owner_pid: ^pid} = CacheShardRead.shard_meta(state.shard_id)
        :ok

      true ->
        Process.sleep(10)
        assert_shard_ready!(pid, attempts - 1)
    end
  end

  defp assert_eventually(fun, attempts \\ 100)
  defp assert_eventually(_fun, 0), do: flunk("condition was not met in time")

  defp assert_eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp restore(key, nil), do: Application.delete_env(:cachepuppy_core, key)
  defp restore(key, value), do: Application.put_env(:cachepuppy_core, key, value)
end
