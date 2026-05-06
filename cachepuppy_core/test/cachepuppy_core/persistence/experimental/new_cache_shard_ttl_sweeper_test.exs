defmodule CachePuppyCore.Persistence.Experimental.NewCacheShardTtlSweeperTest do
  use CachePuppyCore.ExperimentalPersistenceCase, async: false

  alias CachePuppyCore.Persistence.Experimental.NewCacheShardProcess
  alias CachePuppyCore.Persistence.Experimental.NewCacheShardRead
  alias CachePuppyCore.Persistence.Experimental.NewCacheShardTtlSweeper

  test "run_once removes expired keys" do
    {:ok, pid} = start_supervised({NewCacheShardProcess, [shard_id: 9901, name: nil]})
    state = :sys.get_state(pid)

    assert {:ok, %{"v" => 1}} = GenServer.call(pid, {:set, "t", "old", %{"v" => 1}, [ttl_ms: 1]})
    Process.sleep(3)

    assert :ok = NewCacheShardTtlSweeper.run_once(state.ttl_sweeper_pid)
    assert {:ok, nil} = NewCacheShardRead.fast_get(9901, "t", "old")
  end
end
