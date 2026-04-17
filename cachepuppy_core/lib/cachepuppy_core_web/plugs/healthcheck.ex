defmodule CachePuppyCoreWeb.Plugs.Healthcheck do
  @moduledoc false

  alias CachePuppyCore.ClusterQuorumGuard
  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: "/healthz"} = conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
    |> halt()
  end

  def call(%Plug.Conn{request_path: "/readyz"} = conn, _opts) do
    status = ClusterQuorumGuard.quorum_status()

    if status.quorum_met do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, "ready")
      |> halt()
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(
        503,
        "not ready current_nodes=#{status.current_nodes} quorum_threshold=#{status.quorum_threshold}"
      )
      |> halt()
    end
  rescue
    error ->
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(503, "not ready config_error=#{inspect(error)}")
      |> halt()
  end

  def call(conn, _opts), do: conn
end
