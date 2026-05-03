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

  describe "updatedata" do
    test "merges patch into existing map and getdata roundtrips" do
      :ok = put_router_storage_env!("update_merge")
      table = "users"
      key = "upd_merge_#{System.unique_integer([:positive])}"
      base = %{"a" => 1}
      :ok = CacheShardSync.sync!(table, key)
      assert {:ok, ^base} = CacheRouter.setdata(table, key, base)
      assert {:ok, %{"a" => 1, "b" => 2}} = CacheRouter.updatedata(table, key, %{"b" => 2})
      assert {:ok, %{"a" => 1, "b" => 2}} = CacheRouter.getdata(table, key)
    end

    test "updatedata overwrites top-level keys" do
      :ok = put_router_storage_env!("update_overwrite")
      table = "users"
      key = "upd_over_#{System.unique_integer([:positive])}"
      :ok = CacheShardSync.sync!(table, key)
      assert {:ok, _} = CacheRouter.setdata(table, key, %{"a" => 1, "b" => 2})
      assert {:ok, %{"a" => 9, "b" => 2}} = CacheRouter.updatedata(table, key, %{"a" => 9})
    end

    test "updatedata returns not_found for missing key" do
      :ok = put_router_storage_env!("update_missing")
      table = "users"
      key = "upd_miss_#{System.unique_integer([:positive])}"
      :ok = CacheShardSync.sync!(table, key)
      assert {:error, :not_found} = CacheRouter.updatedata(table, key, %{"x" => 1})
    end

    test "updatedata returns not_found after delete" do
      :ok = put_router_storage_env!("update_after_del")
      table = "users"
      key = "upd_del_#{System.unique_integer([:positive])}"
      :ok = CacheShardSync.sync!(table, key)
      assert {:ok, _} = CacheRouter.setdata(table, key, %{"a" => 1})
      assert {:ok, true} = CacheRouter.deldata(table, key)
      assert {:error, :not_found} = CacheRouter.updatedata(table, key, %{"a" => 2})
    end

    test "updatedata returns value_not_mergeable when stored value is not a map" do
      :ok = put_router_storage_env!("update_scalar")
      table = "users"
      key = "upd_scalar_#{System.unique_integer([:positive])}"
      :ok = CacheShardSync.sync!(table, key)
      assert {:ok, "scalar"} = CacheRouter.setdata(table, key, "scalar")
      assert {:error, :value_not_mergeable} = CacheRouter.updatedata(table, key, %{"x" => 1})
    end

    test "updatedata returns invalid_patch when patch is not a map" do
      :ok = put_router_storage_env!("update_bad_patch")
      table = "users"
      key = "upd_patch_#{System.unique_integer([:positive])}"
      :ok = CacheShardSync.sync!(table, key)
      assert {:ok, _} = CacheRouter.setdata(table, key, %{"a" => 1})
      assert {:error, :invalid_patch} = CacheRouter.updatedata(table, key, "not_a_map")
    end

    test "updatedata returns invalid_ttl for ttl_ms 0 in opts" do
      :ok = put_router_storage_env!("update_bad_ttl")
      table = "users"
      key = "upd_ttl_#{System.unique_integer([:positive])}"
      :ok = CacheShardSync.sync!(table, key)
      assert {:ok, _} = CacheRouter.setdata(table, key, %{"a" => 1})
      assert {:error, :invalid_ttl} = CacheRouter.updatedata(table, key, %{}, ttl_ms: 0)
    end

    test "updatedata accepts ttl_ms option and getdata returns merged map" do
      :ok = put_router_storage_env!("update_ttl_opt")
      table = "users"
      key = "upd_ttl_ok_#{System.unique_integer([:positive])}"
      :ok = CacheShardSync.sync!(table, key)
      assert {:ok, _} = CacheRouter.setdata(table, key, %{"a" => 1})
      merged = %{"a" => 1, "b" => 2}

      assert {:ok, ^merged} =
               CacheRouter.updatedata(table, key, %{"b" => 2}, ttl_ms: 3_600_000)

      assert {:ok, ^merged} = CacheRouter.getdata(table, key)
    end

    test "updatedata returns not_found when entry is expired" do
      :ok = put_router_storage_env!("update_expired")
      table = "users"
      key = "upd_exp_#{System.unique_integer([:positive])}"
      :ok = CacheShardSync.sync!(table, key)
      assert {:ok, _} = CacheRouter.setdata(table, key, %{"a" => 1}, ttl_ms: 2)
      Process.sleep(150)
      assert {:ok, nil} = CacheRouter.getdata(table, key)
      assert {:error, :not_found} = CacheRouter.updatedata(table, key, %{"b" => 2})
    end

    test "updatedata returns rehydrating when shard has not completed sync" do
      :ok = put_router_storage_env!("update_rehydrating")
      table = "users"
      key = "upd_rehyd_#{System.unique_integer([:positive])}"
      assert {:error, :rehydrating} = CacheRouter.updatedata(table, key, %{"a" => 1})
    end

    test "updatedata returns invalid_table_or_key for non-binary table" do
      assert {:error, :invalid_table_or_key} = CacheRouter.updatedata(1, "k", %{}, [])
    end
  end

  defp put_router_storage_env!(label) do
    storage_dir = CachePuppyCore.TestTmpDir.path("cache_router_#{label}")

    Application.put_env(:cachepuppy_core, :cache_shard_count, 16)
    Application.put_env(:cachepuppy_core, :cache_flush_interval_ms, 30_000)
    Application.put_env(:cachepuppy_core, :cache_storage_dir, storage_dir)

    on_exit(fn ->
      Application.delete_env(:cachepuppy_core, :cache_shard_count)
      Application.delete_env(:cachepuppy_core, :cache_flush_interval_ms)
      Application.delete_env(:cachepuppy_core, :cache_storage_dir)
    end)

    :ok
  end
end
