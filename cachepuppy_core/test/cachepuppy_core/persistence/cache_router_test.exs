defmodule CachePuppyCore.Persistence.CacheRouterTest do
  use CachePuppyCore.CachePersistenceCase, async: false

  alias CachePuppyCore.CacheShardSync

  test "deterministic set/update/delete via public router APIs" do
    table = "users"
    key = "alice"

    :ok = CacheShardSync.sync!(table, key)

    assert {:ok, %{"name" => "Alice"}} =
             CacheRouter.setdata(table, key, %{"name" => "Alice"}, [])

    assert_eventual_update!(table, key, %{"age" => 10}, {:ok, %{"name" => "Alice", "age" => 10}})

    assert {:ok, true} = CacheRouter.deldata(table, key)
  end

  test "input contract coverage for all public APIs" do
    assert {:error, :invalid_table_or_key} = CacheRouter.setdata(1, "k", %{}, [])
    assert {:error, :invalid_table_or_key} = CacheRouter.setdata("t", 1, %{}, [])
    assert {:error, :invalid_table_or_key} = CacheRouter.setdata("t", "k", %{}, :bad)

    assert {:error, :invalid_table_or_key} = CacheRouter.getdata(1, "k")
    assert {:error, :invalid_table_or_key} = CacheRouter.getdata("t", 1)

    assert {:error, :invalid_table_or_key} = CacheRouter.deldata(1, "k")
    assert {:error, :invalid_table_or_key} = CacheRouter.deldata("t", 1)

    assert {:error, :invalid_table_or_key} = CacheRouter.updatedata(1, "k", %{}, [])
    assert {:error, :invalid_table_or_key} = CacheRouter.updatedata("t", 1, %{}, [])
    assert {:error, :invalid_table_or_key} = CacheRouter.updatedata("t", "k", %{}, :bad)
  end

  test "shard startup is idempotent and owner node is discoverable", %{storage_dir: storage_dir} do
    :ok = File.mkdir_p(storage_dir)
    {:ok, shard_id} = CacheRouter.shard_id_for_entry("users", "bob")

    assert {:ok, pid1} = CacheRouter.ensure_shard_started(shard_id)
    assert is_pid(pid1)

    assert {:ok, pid2} = CacheRouter.ensure_shard_started(shard_id)
    assert is_pid(pid2)

    assert {:ok, owner_node} = CacheRouter.owner_node_for_shard(shard_id)
    assert owner_node == node()
  end

  test "shard_id helpers validate shard_count edge behavior" do
    old_shards = Application.get_env(:cachepuppy_core, :cache_shard_count)

    try do
      Application.put_env(:cachepuppy_core, :cache_shard_count, 0)
      assert {:error, :invalid_shard_count} = CacheRouter.shard_id_for_key("abc")
      assert {:error, :invalid_shard_count} = CacheRouter.shard_id_for_entry("t", "k")
    after
      if old_shards == nil do
        Application.delete_env(:cachepuppy_core, :cache_shard_count)
      else
        Application.put_env(:cachepuppy_core, :cache_shard_count, old_shards)
      end
    end
  end

  test "local remote_* methods match router contracts" do
    table = "remote"
    key = "k1"

    :ok = CacheShardSync.sync!(table, key)
    {:ok, shard_id} = CacheRouter.shard_id_for_entry(table, key)
    {:ok, pid} = CacheRouter.ensure_shard_started(shard_id)

    assert {:ok, 1} = CacheRouter.remote_setdata(pid, table, key, 1, [])
    assert {:ok, 1} = CacheRouter.remote_getdata(shard_id, table, key)
    assert {:ok, %{"a" => 1}} = CacheRouter.remote_setdata(pid, table, key, %{"a" => 1}, [])

    assert {:ok, %{"a" => 1, "b" => 2}} =
             CacheRouter.remote_updatedata(pid, table, key, %{"b" => 2}, [])

    assert {:ok, true} = CacheRouter.remote_deldata(pid, table, key)
    assert {:ok, nil} = CacheRouter.remote_getdata(shard_id, table, key)
  end

  test "shard unavailability maps to shard_unavailable tuple" do
    table = "users"
    key = "gone"

    :ok = CacheShardSync.sync!(table, key)
    {:ok, shard_id} = CacheRouter.shard_id_for_entry(table, key)
    {:ok, pid} = CacheRouter.ensure_shard_started(shard_id)

    :ok = Horde.DynamicSupervisor.terminate_child(CachePuppyCore.CacheShardSupervisor, pid)

    assert {:error, {:shard_unavailable, _reason}} =
             CacheRouter.remote_setdata(pid, table, key, %{"x" => 1}, [])

    assert {:error, {:shard_unavailable, _reason}} =
             CacheRouter.remote_deldata(pid, table, key)

    assert {:error, {:shard_unavailable, _reason}} =
             CacheRouter.remote_updatedata(pid, table, key, %{"x" => 2}, [])
  end

  defp assert_eventual_update!(table, key, patch, expected, attempts \\ 6)

  defp assert_eventual_update!(_table, _key, _patch, expected, 0) do
    flunk("expected update result #{inspect(expected)} after retries")
  end

  defp assert_eventual_update!(table, key, patch, expected, attempts) do
    case CacheRouter.updatedata(table, key, patch, []) do
      ^expected ->
        :ok

      {:error, :not_found} ->
        _ = CacheRouter.setdata(table, key, %{"name" => "Alice"}, [])
        Process.sleep(5)
        assert_eventual_update!(table, key, patch, expected, attempts - 1)

      other ->
        flunk("expected #{inspect(expected)}, got #{inspect(other)}")
    end
  end
end
