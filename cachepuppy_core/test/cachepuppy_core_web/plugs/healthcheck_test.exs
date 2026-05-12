defmodule CachePuppyCoreWeb.Plugs.HealthcheckTest do
  use CachePuppyCoreWeb.ConnCase, async: true

  alias CachePuppyCoreWeb.Plugs.Healthcheck

  test "/healthz returns ok", %{conn: conn} do
    conn =
      conn
      |> Map.put(:request_path, "/healthz")
      |> Healthcheck.call([])

    assert conn.halted
    assert conn.status == 200
    assert conn.resp_body == "ok"
  end

  test "/readyz falls through", %{conn: conn} do
    conn =
      conn
      |> Map.put(:request_path, "/readyz")
      |> Healthcheck.call([])

    refute conn.halted
    assert is_nil(conn.status)
  end
end
