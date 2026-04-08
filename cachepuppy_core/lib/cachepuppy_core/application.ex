defmodule CachePuppyCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CachePuppyCoreWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:cachepuppy_core, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CachePuppyCore.PubSub},
      CachePuppyCoreWeb.Presence,
      # Start a worker by calling: CachePuppyCore.Worker.start_link(arg)
      # {CachePuppyCore.Worker, arg},
      # Start to serve requests, typically the last entry
      CachePuppyCoreWeb.Endpoint
    ]

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
