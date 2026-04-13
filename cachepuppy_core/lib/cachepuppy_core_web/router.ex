defmodule CachePuppyCoreWeb.Router do
  use CachePuppyCoreWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", CachePuppyCoreWeb do
    pipe_through :api

    get "/health", HealthController, :show
    post "/cache/setdata", CacheController, :setdata
    post "/cache/getdata", CacheController, :getdata
  end
end
