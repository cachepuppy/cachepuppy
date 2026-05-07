defmodule CachePuppyCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :ok = CachePuppyCore.Workflow.WorkflowStore.ensure_table()

    topologies = Application.get_env(:libcluster, :topologies, [])

    quorum_guard_children =
      if CachePuppyCore.Persistence.CacheConfig.quorum_guard_enabled?() do
        [{CachePuppyCore.ClusterQuorumGuard, []}]
      else
        []
      end

    children =
      [
        CachePuppyCoreWeb.Telemetry,
        {Finch, name: CachePuppyCore.Finch},
        {Task.Supervisor, name: CachePuppyCore.FlushTaskSupervisor},
        {Cluster.Supervisor, [topologies, [name: CachePuppyCore.ClusterSupervisor]]},
        {Phoenix.PubSub, name: CachePuppyCore.PubSub},
        {Horde.Registry, [name: CachePuppyCore.TopicRegistry, keys: :unique, members: :auto]},
        {Horde.DynamicSupervisor,
         [name: CachePuppyCore.TopicSupervisor, strategy: :one_for_one, members: :auto]},
        {Horde.Registry,
         [name: CachePuppyCore.CacheShardRegistry, keys: :unique, members: :auto]},
        {Horde.DynamicSupervisor,
         [name: CachePuppyCore.CacheShardSupervisor, strategy: :one_for_one, members: :auto]},
        {Horde.Registry, [name: CachePuppyCore.WorkflowRegistry, keys: :unique, members: :auto]},
        {Horde.DynamicSupervisor,
         [name: CachePuppyCore.WorkflowSupervisor, strategy: :one_for_one, members: :auto]},
        CachePuppyCoreWeb.Presence
        # Start a worker by calling: CachePuppyCore.Worker.start_link(arg)
        # {CachePuppyCore.Worker, arg},
        # Start to serve requests, typically the last entry
      ] ++ quorum_guard_children ++ [CachePuppyCoreWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CachePuppyCore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CachePuppyCoreWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
