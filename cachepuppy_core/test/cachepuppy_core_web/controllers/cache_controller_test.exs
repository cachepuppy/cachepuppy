defmodule CachePuppyCoreWeb.CacheControllerTest do
  use CachePuppyCoreWeb.ConnCase, async: true

  test "setdata and getdata via http api", %{conn: conn} do
    key = "http_key_#{System.unique_integer([:positive])}"
    value = %{"flag" => true}

    conn = post(conn, ~p"/api/cache/setdata", %{"key" => key, "value" => value})
    assert %{"key" => ^key, "value" => ^value} = json_response(conn, 200)

    conn = post(build_conn(), ~p"/api/cache/getdata", %{"key" => key})
    assert %{"key" => ^key, "value" => ^value} = json_response(conn, 200)
  end

  test "setdata rejects invalid payload", %{conn: conn} do
    conn = post(conn, ~p"/api/cache/setdata", %{"key" => 123, "value" => "x"})
    assert %{"reason" => "invalid_payload"} = json_response(conn, 400)
  end
end
