import Config

config :cachepuppy_core,
  cache_wal_segment_max_bytes: 200,
  cache_snapshot_min_wal_bytes: 2_000,
  cache_snapshot_interval_ms: 30_000
