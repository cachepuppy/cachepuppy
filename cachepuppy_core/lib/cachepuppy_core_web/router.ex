defmodule CachePuppyCoreWeb.Router do
  use CachePuppyCoreWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", CachePuppyCoreWeb do
    pipe_through :api

    get "/health", HealthController, :show, log: false
    post "/workflows", WorkflowController, :create
    get "/workflows/:id", WorkflowController, :show
    post "/workflows/:id/steps", StepController, :add_step
    post "/workflows/:id/parallel", StepController, :add_parallel
    post "/workflows/:id/parallel/merge_now", StepController, :merge_now
    post "/workflows/:id/resume", StepController, :resume
    post "/workflows/:id/retry", StepController, :retry_step
    post "/workflows/:id/end", StepController, :end_workflow
    post "/cache/setdata", CacheController, :setdata
    post "/cache/getdata", CacheController, :getdata
    post "/cache/updatedata", CacheController, :updatedata
    post "/cache/deletedata", CacheController, :deletedata
  end

  scope "/api/server/v1", CachePuppyCoreWeb do
    pipe_through :api

    put "/topics/:topic/state", ServerTopicController, :put_state
    get "/topics/:topic/state", ServerTopicController, :get_state
    delete "/topics/:topic", ServerTopicController, :delete_topic
    post "/topics/:topic/messages", ServerTopicController, :post_message
    get "/topics/:topic/presence", ServerTopicController, :get_presence
  end
end
