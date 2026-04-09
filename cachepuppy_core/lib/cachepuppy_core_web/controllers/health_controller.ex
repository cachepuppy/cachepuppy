defmodule CachePuppyCoreWeb.HealthController do
  use CachePuppyCoreWeb, :controller

  def show(conn, _params) do
    json(conn, %{
      status: "ok",
      service: "cachepuppy_core",
      node: to_string(Node.self()),
      cluster_size: length(Node.list()) + 1,
      connected_nodes: Enum.map(Node.list(), &to_string/1)
    })
  end
end
