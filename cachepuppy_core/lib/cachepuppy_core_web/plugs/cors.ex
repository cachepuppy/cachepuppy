defmodule CachePuppyCoreWeb.Plugs.CORS do
  @moduledoc false

  import Plug.Conn

  @allow_methods "GET,POST,OPTIONS"
  @allow_headers "content-type,authorization"
  @max_age "86400"

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: "/api/" <> _rest} = conn, _opts) do
    conn =
      conn
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("access-control-allow-methods", @allow_methods)
      |> put_resp_header("access-control-allow-headers", @allow_headers)
      |> put_resp_header("access-control-max-age", @max_age)

    if conn.method == "OPTIONS" do
      conn
      |> send_resp(204, "")
      |> halt()
    else
      conn
    end
  end

  def call(conn, _opts), do: conn
end
