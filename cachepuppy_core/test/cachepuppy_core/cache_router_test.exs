defmodule CachePuppyCore.CacheRouterTest do
  use ExUnit.Case, async: true

  alias CachePuppyCore.CacheRouter

  test "shard hashing is deterministic" do
    Application.put_env(:cachepuppy_core, :cache_shard_count, 32)

    on_exit(fn ->
      Application.delete_env(:cachepuppy_core, :cache_shard_count)
    end)

    assert {:ok, shard_id} = CacheRouter.shard_id_for_key("alpha")
    assert {:ok, ^shard_id} = CacheRouter.shard_id_for_key("alpha")
  end

  test "setdata and getdata roundtrip through shard routing" do
    storage_dir =
      Path.join(System.tmp_dir!(), "cache_router_#{System.unique_integer([:positive])}")

    Application.put_env(:cachepuppy_core, :cache_shard_count, 16)
    Application.put_env(:cachepuppy_core, :cache_flush_interval_ms, 30_000)
    Application.put_env(:cachepuppy_core, :cache_storage_dir, storage_dir)

    on_exit(fn ->
      Application.delete_env(:cachepuppy_core, :cache_shard_count)
      Application.delete_env(:cachepuppy_core, :cache_flush_interval_ms)
      Application.delete_env(:cachepuppy_core, :cache_storage_dir)
    end)

    key = "router_key_#{System.unique_integer([:positive])}"
    value = %{"enabled" => true}

    table = "users"

    assert {:ok, ^value} = CacheRouter.setdata(table, key, value)
    assert {:ok, ^value} = CacheRouter.getdata(table, key)
    assert {:ok, nil} = CacheRouter.getdata(table, "#{key}_missing")
  end

  test "single-node cluster resolves owner to current node via horde placement" do
    assert {:ok, owner} = CacheRouter.owner_node_for_shard(5)
    assert owner == node()
  end
end
