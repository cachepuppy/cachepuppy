# Cache Flush Engine

This document explains each function in `CachePuppyCore.Persistence.CacheFlushEngine` and how they fit together.

## Quick Flow (Gist First)

1. A cache write comes into a shard process.
2. The shard appends that write to its WAL file immediately.
3. The shard updates ETS in-memory state.
4. On periodic maintenance ticks, WAL data is synced to disk and rotated into new segment files when large.
5. Snapshot checks run infrequently; when thresholds are met, a background snapshot of ETS is written.
6. After snapshot success, a checkpoint is written and older WAL segments are pruned.
7. On restart, the shard loads snapshot first and then replays WAL records after the checkpoint to catch up.
8. If WAL tail bytes are corrupted/incomplete (for example after crash), only the valid prefix is replayed and the bad tail is truncated.

## Overview

`CacheFlushEngine` manages shard-local flush persistence with:
- WAL append and periodic sync
- WAL segment rotation
- Snapshot writing and checkpointing

The engine struct stores runtime state such as current WAL segment, open file descriptor, sync bookkeeping, and snapshot progress hints.

## Public Functions

### `init/1`
- Reads dynamic option: `:shard_id`.
- Reads static settings from `CacheConfig` (storage dir, WAL segment size).
- Ensures the storage directory exists.
- Detects the latest WAL segment and byte size.
- Opens that segment in append mode and initializes engine state.
- Returns `{:ok, engine}`.

### `close/1`
- If no WAL file is open, returns state unchanged.
- Otherwise syncs and closes the current WAL file descriptor.
- Returns updated engine with `current_wal_fd: nil`.

### `append_set/4`
- Encodes one write operation (`{:set, table, key, value, ts}`) as a length-prefixed binary record.
- Appends the record to current WAL file.
- Updates in-memory byte counters:
  - `current_wal_bytes`
  - `wal_bytes_since_snapshot`
  - `pending_sync_bytes`
- Returns `{:ok, updated_engine}` or file write error.

### `maybe_sync/1`
- No-op when `pending_sync_bytes` is `0`.
- Calls `:file.sync/1` whenever there are pending WAL bytes.
- Resets pending-sync counters on success.
- Returns `{:ok, engine}` or `{:error, reason}`.

### `maybe_rotate/1`
- Checks if current segment exceeds `CacheConfig.wal_segment_max_bytes/0`.
- If yes:
  - syncs and closes current segment
  - increments segment sequence
  - opens new segment file
  - resets per-segment counters
- Returns `{:ok, engine}` or file error.

### `should_snapshot?/3`
- Returns `true` only when both are met:
  - `wal_bytes_since_snapshot >= snapshot_min_wal_bytes`
  - elapsed time since `last_snapshot_at_ms >= snapshot_interval_ms`

### `mark_snapshot_started/1`
- Updates `last_snapshot_at_ms` to current timestamp.
- Used to avoid duplicate back-to-back snapshot starts.

### `snapshot_cutoff_seq/1`
- Returns current WAL segment sequence.
- Used as the snapshot checkpoint boundary for pruning.

### `finalize_snapshot/2`
- Writes checkpoint metadata (`snapshot_cutoff_seq`, `updated_at_ms`).
- Prunes WAL segments older than cutoff.
- Resets `wal_bytes_since_snapshot`.
- Returns `{:ok, updated_engine}`.

### `write_snapshot/2`
- Writes ETS table to temp snapshot via `:ets.tab2file(..., sync: true)`.
- Atomically promotes temp snapshot with `File.rename/2`.
- Returns `:ok` or error tuple.

## Internal Modules

### `CachePuppyCore.Persistence.CacheUtils`
- Owns shared helpers for path conventions and WAL segment listing.

### `CachePuppyCore.Persistence.CacheRecoveryEngine`
- Owns snapshot + WAL replay flow and tail-corruption truncation logic.

## Private Functions

### `encode_record/1`
- Serializes term and prefixes payload length as 32-bit unsigned integer.

### `latest_wal_segment/2`
- Finds newest WAL segment and size.
- Defaults to `{1, 0}` if no WAL exists.

### `prune_wal_segments/3`
- Removes WAL segment files where `seq < cutoff_seq`.

### `write_term_file/2`
- Writes erlang term to `path.tmp` then renames to final path.
- Used for checkpoint atomicity.
