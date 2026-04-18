defmodule CachePuppyCore.Persistence.CacheConfig do
  @moduledoc false

  @default_shard_count 64
  @default_rpc_timeout_ms 5_000
  @default_flush_interval_ms 5_000
  @default_storage_dir "tmp/cache_shards"
  @default_wal_segment_max_bytes 1_048_576
  @default_snapshot_interval_ms 60_000
  @default_snapshot_min_wal_bytes 262_144
  @default_recovery_max_segments 1_024
  @default_quorum_poll_interval_ms 2_000
  @default_quorum_grace_ms 20_000
  @default_ttl_sweep_interval_ms 10_000
  @default_ttl_ms_max 86_400_000 * 30

  def shard_count do
    Application.get_env(:cachepuppy_core, :cache_shard_count, @default_shard_count)
  end

  def rpc_timeout_ms do
    Application.get_env(:cachepuppy_core, :cache_rpc_timeout_ms, @default_rpc_timeout_ms)
  end

  def shard_process_opts(shard_id) when is_integer(shard_id) do
    [shard_id: shard_id]
  end

  def flush_interval_ms do
    Application.get_env(:cachepuppy_core, :cache_flush_interval_ms, @default_flush_interval_ms)
  end

  def storage_dir do
    Application.get_env(:cachepuppy_core, :cache_storage_dir, @default_storage_dir)
  end

  def wal_segment_max_bytes do
    Application.get_env(
      :cachepuppy_core,
      :cache_wal_segment_max_bytes,
      @default_wal_segment_max_bytes
    )
  end

  def snapshot_interval_ms do
    Application.get_env(
      :cachepuppy_core,
      :cache_snapshot_interval_ms,
      @default_snapshot_interval_ms
    )
  end

  def snapshot_min_wal_bytes do
    Application.get_env(
      :cachepuppy_core,
      :cache_snapshot_min_wal_bytes,
      @default_snapshot_min_wal_bytes
    )
  end

  def recovery_max_segments do
    Application.get_env(
      :cachepuppy_core,
      :cache_recovery_max_segments,
      @default_recovery_max_segments
    )
  end

  def expected_nodes do
    Application.fetch_env!(:cachepuppy_core, :cache_expected_nodes)
  end

  def quorum_poll_interval_ms do
    Application.get_env(
      :cachepuppy_core,
      :cache_quorum_poll_interval_ms,
      @default_quorum_poll_interval_ms
    )
  end

  def quorum_grace_ms do
    Application.get_env(:cachepuppy_core, :cache_quorum_grace_ms, @default_quorum_grace_ms)
  end

  def quorum_stop_enabled? do
    Application.get_env(:cachepuppy_core, :cache_quorum_stop_enabled, true)
  end

  def quorum_guard_enabled? do
    Application.get_env(:cachepuppy_core, :cache_quorum_guard_enabled, true)
  end

  def ttl_sweep_interval_ms do
    Application.get_env(
      :cachepuppy_core,
      :cache_ttl_sweep_interval_ms,
      @default_ttl_sweep_interval_ms
    )
  end

  def ttl_ms_max do
    Application.get_env(:cachepuppy_core, :cache_ttl_ms_max, @default_ttl_ms_max)
  end
end
