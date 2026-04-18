# Cache Flush Engine

This document explains each function in `CachePuppyCore.Persistence.CacheFlushEngine` and how they fit together.

## Quick Flow (Gist First)

1. A cache write comes into a shard process.
2. The shard issues a synchronous `GenServer.call` to the flush engine so the WAL append completes before ETS is updated.
3. On periodic maintenance ticks, WAL data is synced to disk and rotated into new segment files when large.
4. Snapshot checks run infrequently; when thresholds are met, the engine syncs, rolls to a new WAL segment, then a background task materializes `snapshot.ets` by loading the previous snapshot (if any) and replaying closed WAL segments from the checkpoint through the rolled-off segment.
5. After snapshot success, a checkpoint is written and older WAL segments are pruned.
6. On restart, the shard loads snapshot first and then replays WAL records after the checkpoint to catch up.
7. If WAL tail bytes are corrupted/incomplete (for example after crash), only the valid prefix is replayed and the bad tail is truncated (recovery path).

## Overview

`CacheFlushEngine` manages shard-local flush persistence with:

- WAL append (via `handle_call` / `persist_set`) and periodic sync
- WAL segment rotation
- WAL-derived snapshot writing and checkpointing

The engine struct stores runtime state such as current WAL segment, open file descriptor, sync bookkeeping, and snapshot progress hints.

## Public Functions

### `init/1`

- Reads dynamic option: `:shard_id`, `:table`, `:owner_epoch`, snapshot thresholds.
- Reads static settings from `CacheConfig` (storage dir, WAL segment size).
- Ensures the storage directory exists.
- Detects the latest WAL segment and byte size.
- Opens that segment in append mode and initializes engine state.
- Schedules periodic flush ticks.

### `persist_set/4`

- `GenServer.call` handler: when ownership metadata is valid, encodes and appends one `{:set, table, key, value, ts}` record, then may rotate if the segment exceeds the configured max size.
- Returns `:ok` or `{:error, reason}` (including `{:error, :stale_owner}` when ownership is invalid).
- Does not fsync on every append; pending bytes are synced on `:flush_tick`.

### `terminate/2`

- Syncs and closes the WAL file descriptor.

## Internal behaviour

### Maintenance (`:flush_tick`)

- `maybe_sync` then `maybe_rotate` when the owner is still valid.

### Snapshots

- When allowed and thresholds are met: `maybe_sync`, then a forced WAL segment roll so all durable data through the previous segment is in closed files.
- A `Task` runs `CacheWalReplay.materialize_snapshot_from_wal/4` (checkpoint from disk, closed segment range), then `finalize_snapshot/2` writes the checkpoint and prunes older WAL segments.

## Related modules

### `CachePuppyCore.Persistence.CacheUtils`

- Path conventions and WAL segment listing.

### `CachePuppyCore.Persistence.CacheWalReplay`

- WAL decode, replay into an ETS table, optional tail truncation on disk, and snapshot materialization from WAL + prior snapshot.

### `CachePuppyCore.Persistence.CacheRecoveryEngine`

- Loads `snapshot.ets` then replays WAL from the checkpoint onward (uses `CacheWalReplay`).
