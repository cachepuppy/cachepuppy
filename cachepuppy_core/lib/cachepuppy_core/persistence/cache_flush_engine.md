# Cache Flush Engine

This document explains `CachePuppyCore.Persistence.CacheFlushEngine` and how persistence integrates with the shard process.

## Quick Flow (Gist First)

1. `CacheShardProcess` owns WAL state as a nested `%FlushState{}` struct.
2. Each `set` calls `CacheFlushEngine.persist_set/4` before updating ETS.
3. The shard schedules `:flush_tick` to itself (`Process.send_after`); on each tick it calls `CacheFlushEngine.on_flush_tick/1` for sync, optional rotate, and snapshot eligibility.
4. Snapshot work still runs under `Task.Supervisor.async_nolink` from the flush engine when a tick decides to start a snapshot; replay/`tab2file` stays off the shard’s synchronous `set` path.
5. After snapshot success, `on_snapshot_message/2` applies checkpoint + prune via `finalize_snapshot`.

## Overview

`CacheFlushEngine` is a **module** operating on an explicit `%FlushState{}` struct (WAL fd, segment seq, snapshot task ref, byte counters). The **shard GenServer** is the only production process that holds `%FlushState{}` and routes timer and task messages; **flush tick timers** live on the shard, not on `%FlushState{}`.

## Public API (selected)

### `open/2`

`open(shard_id, owner_epoch)`. Creates storage dir if needed, opens the latest WAL segment, returns `{:ok, %FlushState{}}`.

### `close/1`

Syncs and closes the WAL fd on `%FlushState{}`.

### `persist_set/4`

`persist_set(flush, table, key, value)` — owner check (from `flush.owner_epoch`), append, optional size-based rotate. Returns `{:ok, new_flush}` or `{:error, reason}`.

### `on_flush_tick/1`

Runs periodic sync + rotate (when owner valid), then `maybe_start_snapshot` when allowed.

### `on_snapshot_message/2`

Handles task completion tuples (`{:snapshot_done, ...}`) and updates flush state (checkpoint, prune, clear task ref).

### `clear_snapshot_task_ref/1`

Clears `snapshot_task_ref` after a failed or abandoned snapshot task.

## Tests

Persistence behavior is covered by `CacheShardProcess` integration tests and by calling `CacheFlushEngine` functions directly where no GenServer mailbox is required (for example `persist_set/4` with a `%FlushState{}` from `open/2`).

## Related modules

- `CacheWalReplay` — WAL replay and snapshot materialization.
- `CacheRecoveryEngine` — startup recovery using `CacheWalReplay`.
