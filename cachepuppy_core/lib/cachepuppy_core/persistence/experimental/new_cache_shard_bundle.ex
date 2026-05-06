defmodule CachePuppyCore.Persistence.Experimental.NewCacheShardBundle do
  @moduledoc """
  Thin `Supervisor` with a single `NewCacheShardProcess` child.

  The shard process starts and links `NewCacheShardFlushProcess` and
  `NewCacheShardMaintenanceProcess` internally; this bundle exists for a
  conventional OTP entrypoint (`start_link/1`) without adding more layers.
  """

  use Supervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    sup_name = Keyword.get(opts, :sup_name)

    if sup_name do
      Supervisor.start_link(__MODULE__, opts, name: sup_name)
    else
      Supervisor.start_link(__MODULE__, opts)
    end
  end

  @impl true
  def init(opts) do
    children = [
      {CachePuppyCore.Persistence.Experimental.NewCacheShardProcess, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
