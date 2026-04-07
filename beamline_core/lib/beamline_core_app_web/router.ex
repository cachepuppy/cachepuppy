defmodule BeamlineCoreAppWeb.Router do
  use BeamlineCoreAppWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", BeamlineCoreAppWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end
end
