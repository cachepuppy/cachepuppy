defmodule CachePuppyCore.Persistence.Experimental.NewCacheShardProcessTest do
  use CachePuppyCore.ExperimentalPersistenceCase, async: false

  alias CachePuppyCore.Persistence.Experimental.NewCacheOwnerMeta
  alias CachePuppyCore.Persistence.Experimental.NewCacheShardProcess
  alias CachePuppyCore.Persistence.Experimental.NewCacheShardRead

  test "startup rehydrate remains stable across repeated boots" do
    Enum.each(1..20, fn offset ->
      shard_id = 10_000 + offset
      {:ok, pid} = start_supervised({NewCacheShardProcess, [shard_id: shard_id, name: nil]})
      assert_shard_ready!(pid)
      assert Process.alive?(pid)
    end)
  end

  test "rehydrate_sync is idempotent and swapped table is owned by shard" do
    {:ok, pid} = start_supervised({NewCacheShardProcess, [shard_id: 20_001, name: nil]})
    assert_shard_ready!(pid)

    assert :ok = GenServer.call(pid, :rehydrate_sync)
    assert :ok = GenServer.call(pid, :rehydrate_sync)

    state = :sys.get_state(pid)
    assert state.ready?
    assert state.owner_valid?
    assert :ets.info(state.table, :owner) == pid
  end

  test "readiness gate rejects writes while rehydrating" do
    {:ok, pid} = start_supervised({NewCacheShardProcess, [shard_id: 20_002, name: nil]})
    assert_shard_ready!(pid)

    :sys.replace_state(pid, fn st -> %{st | ready?: false} end)

    assert {:error, :rehydrating} = GenServer.call(pid, {:set, "t", "k", 1, []})
    assert {:error, :rehydrating} = GenServer.call(pid, {:delete, "t", "k"})
    assert {:error, :rehydrating} = GenServer.call(pid, {:update, "t", "k", %{"x" => 1}, []})
  end

  test "owner invalidation rejects mutations and snapshot", %{storage_dir: storage_dir} do
    shard_id = 20_003
    {:ok, pid} = start_supervised({NewCacheShardProcess, [shard_id: shard_id, name: nil]})
    assert_shard_ready!(pid)

    state = :sys.get_state(pid)
    _new_epoch = NewCacheOwnerMeta.claim_ownership(storage_dir, shard_id, to_string(node()))

    send(pid, :owner_check_tick)
    Process.sleep(10)

    state_after = :sys.get_state(pid)
    refute state_after.owner_valid?

    assert {:error, :stale_owner} = GenServer.call(pid, {:set, "t", "k", 1, []})
    assert {:error, :stale_owner} = GenServer.call(pid, {:delete, "t", "k"})
    assert {:error, :stale_owner} = GenServer.call(pid, {:update, "t", "k", %{"x" => 1}, []})
    assert {:error, :stale_owner} = GenServer.call(pid, :snapshot)

    # State remains coherent even after stale-owner rejections.
    assert state_after.table == :sys.get_state(pid).table
    assert state.owner_epoch == state_after.owner_epoch
  end

  test "mutation contract coverage for ttl, patching, not_found and delete idempotence" do
    {:ok, pid} = start_supervised({NewCacheShardProcess, [shard_id: 20_004, name: nil]})
    assert_shard_ready!(pid)

    assert {:error, :invalid_ttl} = GenServer.call(pid, {:set, "t", "k", 1, [ttl_ms: -1]})
    assert {:error, :invalid_patch} = GenServer.call(pid, {:update, "t", "k", 1, []})
    assert {:error, :not_found} = GenServer.call(pid, {:update, "t", "missing", %{"x" => 1}, []})
    assert {:ok, false} = GenServer.call(pid, {:delete, "t", "missing"})

    assert {:ok, 10} = GenServer.call(pid, {:set, "t", "scalar", 10, []})

    assert {:error, :value_not_mergeable} =
             GenServer.call(pid, {:update, "t", "scalar", %{"x" => 1}, []})
  end

  test "update carries ttl forward when ttl_ms omitted" do
    {:ok, pid} = start_supervised({NewCacheShardProcess, [shard_id: 20_005, name: nil]})
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

  test "snapshot succeeds when owner valid" do
    {:ok, pid} = start_supervised({NewCacheShardProcess, [shard_id: 20_006, name: nil]})
    assert_shard_ready!(pid)

    assert {:ok, %{"v" => 1}} = GenServer.call(pid, {:set, "snap", "k", %{"v" => 1}, []})
    assert :ok = GenServer.call(pid, :snapshot)
  end

  defp assert_shard_ready!(pid, attempts \\ 200)

  defp assert_shard_ready!(_pid, 0), do: flunk("shard did not become ready")

  defp assert_shard_ready!(pid, attempts) do
    state = :sys.get_state(pid)

    cond do
      state.ready? and state.owner_valid? ->
        assert %{ready?: true, owner_pid: ^pid} = NewCacheShardRead.shard_meta(state.shard_id)
        :ok

      true ->
        Process.sleep(10)
        assert_shard_ready!(pid, attempts - 1)
    end
  end
end
