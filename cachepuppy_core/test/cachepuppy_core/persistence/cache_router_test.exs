defmodule CachePuppyCore.Persistence.CacheRouterTest do
  use ExUnit.Case, async: false

  alias CachePuppyCore.CacheShardSync
  alias CachePuppyCore.Persistence.CacheRouter

  setup do
    :ok = CacheShardSync.reset_horde_shards!()
    :ok
  end

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
      CachePuppyCore.TestTmpDir.path("cache_router")

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

    :ok = CacheShardSync.sync!(table, key)
    assert {:ok, ^value} = CacheRouter.setdata(table, key, value)
    assert {:ok, ^value} = CacheRouter.getdata(table, key)

    missing_key = "#{key}_missing"
    :ok = CacheShardSync.sync!(table, missing_key)
    assert {:ok, nil} = CacheRouter.getdata(table, missing_key)
  end

  test "single-node cluster resolves owner to current node via horde placement" do
    assert {:ok, owner} = CacheRouter.owner_node_for_shard(5)
    assert owner == node()
  end

  test "deldata removes key and is idempotent" do
    storage_dir =
      CachePuppyCore.TestTmpDir.path("cache_router_del")

    Application.put_env(:cachepuppy_core, :cache_shard_count, 16)
    Application.put_env(:cachepuppy_core, :cache_flush_interval_ms, 30_000)
    Application.put_env(:cachepuppy_core, :cache_storage_dir, storage_dir)

    on_exit(fn ->
      Application.delete_env(:cachepuppy_core, :cache_shard_count)
      Application.delete_env(:cachepuppy_core, :cache_flush_interval_ms)
      Application.delete_env(:cachepuppy_core, :cache_storage_dir)
    end)

    table = "users"
    key = "del_key_#{System.unique_integer([:positive])}"
    value = "gone"

    :ok = CacheShardSync.sync!(table, key)
    assert {:ok, ^value} = CacheRouter.setdata(table, key, value)
    assert {:ok, true} = CacheRouter.deldata(table, key)
    assert {:ok, false} = CacheRouter.deldata(table, key)
    assert {:ok, nil} = CacheRouter.getdata(table, key)
  end

  test "setdata with ttl_ms option roundtrips get" do
    storage_dir =
      CachePuppyCore.TestTmpDir.path("cache_router_ttl")

    Application.put_env(:cachepuppy_core, :cache_shard_count, 16)
    Application.put_env(:cachepuppy_core, :cache_flush_interval_ms, 30_000)
    Application.put_env(:cachepuppy_core, :cache_storage_dir, storage_dir)

    on_exit(fn ->
      Application.delete_env(:cachepuppy_core, :cache_shard_count)
      Application.delete_env(:cachepuppy_core, :cache_flush_interval_ms)
      Application.delete_env(:cachepuppy_core, :cache_storage_dir)
    end)

    table = "users"
    key = "ttl_key_#{System.unique_integer([:positive])}"
    value = "with_ttl"

    :ok = CacheShardSync.sync!(table, key)
    assert {:ok, ^value} = CacheRouter.setdata(table, key, value, ttl_ms: 3_600_000)
    assert {:ok, ^value} = CacheRouter.getdata(table, key)
  end
end
