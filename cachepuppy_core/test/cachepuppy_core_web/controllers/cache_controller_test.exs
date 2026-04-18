defmodule CachePuppyCoreWeb.CacheControllerTest do
  use CachePuppyCoreWeb.ConnCase, async: false

  setup do
    storage_dir =
      Path.join(System.tmp_dir!(), "cache_controller_#{System.unique_integer([:positive])}")

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

    conn = post_until_setdata_ok(conn, ~p"/api/cache/setdata", params)
    assert %{"table" => ^table, "key" => ^key, "value" => ^value} = json_response(conn, 200)

    conn = post_until_ok(build_conn(), ~p"/api/cache/getdata", %{"table" => table, "key" => key})
    assert %{"table" => ^table, "key" => ^key, "value" => ^value} = json_response(conn, 200)
  end

  test "setdata rejects invalid payload", %{conn: conn} do
    conn = post(conn, ~p"/api/cache/setdata", %{"table" => "users", "key" => 123, "value" => "x"})
    assert %{"reason" => "invalid_payload"} = json_response(conn, 400)
  end

  test "cors preflight works for cache api", %{conn: conn} do
    conn = options(conn, ~p"/api/cache/setdata")
    assert response(conn, 204)
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    assert get_resp_header(conn, "access-control-allow-methods") == ["GET,POST,OPTIONS"]
  end

  defp post_until_setdata_ok(conn, path, params, attempts \\ 150)

  defp post_until_setdata_ok(_conn, _path, _params, 0),
    do: flunk("setdata did not succeed while shard rehydrated")

  defp post_until_setdata_ok(conn, path, params, attempts) do
    conn = post(conn, path, params)

    case conn.status do
      200 ->
        conn

      500 ->
        receive do
        after
          20 -> post_until_setdata_ok(build_conn(), path, params, attempts - 1)
        end

      other ->
        flunk("unexpected status #{other} body=#{inspect(conn.resp_body)}")
    end
  end

  defp post_until_ok(conn, path, params, attempts \\ 150)

  defp post_until_ok(_conn, _path, _params, 0),
    do: flunk("request did not succeed while shard rehydrated")

  defp post_until_ok(conn, path, params, attempts) do
    conn = post(conn, path, params)

    case conn.status do
      200 ->
        conn

      500 ->
        receive do
        after
          20 -> post_until_ok(build_conn(), path, params, attempts - 1)
        end

      other ->
        flunk("unexpected status #{other} body=#{inspect(conn.resp_body)}")
    end
  end
end
