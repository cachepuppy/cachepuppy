defmodule CachePuppyCoreWeb.CacheControllerTest do
  use CachePuppyCoreWeb.ConnCase, async: true

  test "setdata and getdata via http api", %{conn: conn} do
    table = "users"
    key = "http_key_#{System.unique_integer([:positive])}"
    value = %{"flag" => true}

    conn = post(conn, ~p"/api/cache/setdata", %{"table" => table, "key" => key, "value" => value})
    assert %{"table" => ^table, "key" => ^key, "value" => ^value} = json_response(conn, 200)

    conn = post(build_conn(), ~p"/api/cache/getdata", %{"table" => table, "key" => key})
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
end
