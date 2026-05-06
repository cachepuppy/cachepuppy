defmodule CachePuppyCore.Persistence.CacheShardTtlSweeperTest do
  use CachePuppyCore.CachePersistenceCase, async: false

  alias CachePuppyCore.Persistence.CacheShardProcess
  alias CachePuppyCore.Persistence.CacheShardRead
  alias CachePuppyCore.Persistence.CacheShardTtlSweeper

  test "run_once removes expired keys" do
    {:ok, pid} = start_supervised({CacheShardProcess, [shard_id: 9901, name: nil]})
    state = :sys.get_state(pid)

    assert {:ok, %{"v" => 1}} = GenServer.call(pid, {:set, "t", "old", %{"v" => 1}, [ttl_ms: 1]})
    Process.sleep(3)

    assert :ok = CacheShardTtlSweeper.run_once(state.ttl_sweeper_pid)
    assert {:ok, nil} = CacheShardRead.fast_get(9901, "t", "old")
  end
end
