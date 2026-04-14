# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :cachepuppy_core,
  generators: [timestamp_type: :utc_datetime],
  topic_idle_timeout_ms: 120_000,
  cache_shard_count: 64,
  cache_ring_virtual_nodes: 128,
  cache_flush_interval_ms: 5_000,
  cache_rpc_timeout_ms: 5_000,
  cache_storage_dir: "tmp/cache_shards",
  cache_wal_segment_max_bytes: 1_048_576,
  cache_snapshot_interval_ms: 60_000,
  cache_snapshot_min_wal_bytes: 262_144,
  cache_recovery_max_segments: 1_024

# Configure the endpoint
config :cachepuppy_core, CachePuppyCoreWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: CachePuppyCoreWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CachePuppyCore.PubSub,
  live_view: [signing_salt: "ifC6PXFX"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
