defmodule CachePuppyCoreWeb.CacheControllerTest do
  use CachePuppyCoreWeb.ConnCase, async: false

  alias CachePuppyCore.CacheShardSync

  setup do
    :ok = CacheShardSync.reset_horde_shards!()

    storage_dir =
      CachePuppyCore.TestTmpDir.path("cache_controller")

    File.mkdir_p!(storage_dir)
    old_storage = Application.get_env(:cachepuppy_core, :cache_storage_dir)
    Application.put_env(:cachepuppy_core, :cache_storage_dir, storage_dir)

    on_exit(fn ->
      _ = File.rm_rf(storage_dir)

      if old_storage == nil do
        Application.delete_env(:cachepuppy_core, :cache_storage_dir)
      else
        Application.put_env(:cachepuppy_core, :cache_storage_dir, old_storage)
      end
    end)

    :ok
  end

  test "setdata and getdata via http api", %{conn: conn} do
    table = "users"
    key = "http_key_#{System.unique_integer([:positive])}"
    value = %{"flag" => true}
    params = %{"table" => table, "key" => key, "value" => value}

    :ok = CacheShardSync.sync!(table, key)

    conn = post(conn, ~p"/api/cache/setdata", params)
    assert %{"table" => ^table, "key" => ^key, "value" => ^value} = json_response(conn, 200)

    conn = post(build_conn(), ~p"/api/cache/getdata", %{"table" => table, "key" => key})
    assert %{"table" => ^table, "key" => ^key, "value" => ^value} = json_response(conn, 200)
  end

  test "setdata rejects invalid payload", %{conn: conn} do
    conn = post(conn, ~p"/api/cache/setdata", %{"table" => "users", "key" => 123, "value" => "x"})
    assert %{"reason" => "invalid_payload"} = json_response(conn, 400)
  end

  test "setdata rejects invalid ttl_ms", %{conn: conn} do
    conn =
      post(conn, ~p"/api/cache/setdata", %{
        "table" => "users",
        "key" => "k",
        "value" => "v",
        "ttl_ms" => 0
      })

    assert %{"reason" => "invalid_ttl_ms"} = json_response(conn, 400)
  end

  test "deletedata removes key", %{conn: conn} do
    table = "users"
    key = "del_http_#{System.unique_integer([:positive])}"
    value = "x"

    :ok = CacheShardSync.sync!(table, key)

    conn =
      post(conn, ~p"/api/cache/setdata", %{
        "table" => table,
        "key" => key,
        "value" => value
      })

    assert %{"table" => ^table, "key" => ^key, "value" => ^value} = json_response(conn, 200)

    conn =
      post(build_conn(), ~p"/api/cache/deletedata", %{"table" => table, "key" => key})

    assert %{"table" => ^table, "key" => ^key, "deleted" => true} = json_response(conn, 200)

    conn =
      post(build_conn(), ~p"/api/cache/deletedata", %{"table" => table, "key" => key})

    assert %{"table" => ^table, "key" => ^key, "deleted" => false} = json_response(conn, 200)

    conn = post(build_conn(), ~p"/api/cache/getdata", %{"table" => table, "key" => key})
    assert %{"table" => ^table, "key" => ^key, "value" => nil} = json_response(conn, 200)
  end

  test "cors preflight works for cache api", %{conn: conn} do
    conn = options(conn, ~p"/api/cache/setdata")
    assert response(conn, 204)
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    assert get_resp_header(conn, "access-control-allow-methods") == ["GET,POST,OPTIONS"]
  end

  test "updatedata merges patch and returns full value", %{conn: conn} do
    table = "users"
    key = "upd_http_#{System.unique_integer([:positive])}"
    :ok = CacheShardSync.sync!(table, key)

    conn =
      post(conn, ~p"/api/cache/setdata", %{
        "table" => table,
        "key" => key,
        "value" => %{"a" => 1}
      })

    assert json_response(conn, 200)

    conn =
      post(build_conn(), ~p"/api/cache/updatedata", %{
        "table" => table,
        "key" => key,
        "patch" => %{"b" => 2}
      })

    assert %{"table" => ^table, "key" => ^key, "value" => %{"a" => 1, "b" => 2}} =
             json_response(conn, 200)
  end

  test "updatedata rejects invalid payload", %{conn: conn} do
    conn =
      post(conn, ~p"/api/cache/updatedata", %{
        "table" => "users",
        "key" => "k",
        "patch" => []
      })

    assert %{"reason" => "invalid_payload"} = json_response(conn, 400)

    conn =
      post(build_conn(), ~p"/api/cache/updatedata", %{"table" => "users", "key" => "k2"})

    assert %{"reason" => "invalid_payload"} = json_response(conn, 400)
  end

  test "updatedata returns not_found when key missing", %{conn: conn} do
    table = "users"
    key = "upd_nf_#{System.unique_integer([:positive])}"
    :ok = CacheShardSync.sync!(table, key)

    conn =
      post(conn, ~p"/api/cache/updatedata", %{
        "table" => table,
        "key" => key,
        "patch" => %{"x" => 1}
      })

    assert %{"reason" => "not_found"} = json_response(conn, 404)
  end

  test "updatedata returns value_not_mergeable for non-map stored value", %{conn: conn} do
    table = "users"
    key = "upd_vm_#{System.unique_integer([:positive])}"
    :ok = CacheShardSync.sync!(table, key)

    conn =
      post(conn, ~p"/api/cache/setdata", %{
        "table" => table,
        "key" => key,
        "value" => "scalar"
      })

    assert json_response(conn, 200)

    conn =
      post(build_conn(), ~p"/api/cache/updatedata", %{
        "table" => table,
        "key" => key,
        "patch" => %{"x" => 1}
      })

    assert %{"reason" => "value_not_mergeable"} = json_response(conn, 400)
  end

  test "updatedata rejects invalid ttl_ms", %{conn: conn} do
    table = "users"
    key = "upd_ttl_http_#{System.unique_integer([:positive])}"
    :ok = CacheShardSync.sync!(table, key)

    _ =
      post(conn, ~p"/api/cache/setdata", %{
      "table" => table,
      "key" => key,
      "value" => %{"a" => 1}
      })

    conn =
      post(build_conn(), ~p"/api/cache/updatedata", %{
        "table" => table,
        "key" => key,
        "patch" => %{},
        "ttl_ms" => 0
      })

    assert %{"reason" => "invalid_ttl_ms"} = json_response(conn, 400)
  end

  test "cors preflight works for updatedata", %{conn: conn} do
    conn = options(conn, ~p"/api/cache/updatedata")
    assert response(conn, 204)
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    assert get_resp_header(conn, "access-control-allow-methods") == ["GET,POST,OPTIONS"]
  end
end
