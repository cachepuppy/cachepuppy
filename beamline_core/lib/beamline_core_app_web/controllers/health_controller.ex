defmodule BeamlineCoreAppWeb.HealthController do
  use BeamlineCoreAppWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok", service: "beamline_core_app"})
  end
end
