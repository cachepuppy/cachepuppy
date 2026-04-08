defmodule CachePuppyCoreWeb.HealthController do
  use CachePuppyCoreWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok", service: "cachepuppy_core"})
  end
end
