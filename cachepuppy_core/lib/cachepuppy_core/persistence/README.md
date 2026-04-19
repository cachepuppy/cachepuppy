# Persistence layer

This folder holds cache durability: shard ownership, WAL append/sync/rotate, snapshots, recovery, routing, and config. The **shard GenServer** (`CachePuppyCore.Persistence.CacheShardProcess`) orchestrates timers and recovery; **`CacheFlushEngine`** mutates `%FlushState{}`; **`CacheRecoveryEngine`** rebuilds ETS from snapshot + WAL on startup.

---

## Shard process (`CachePuppyCore.Persistence.CacheShardProcess`)

Why shard ownership is claimed, validated, and refreshed.

### Why this exists

Shard processes can move between nodes (failover/rebalance), while persistence files are shared.  
Without ownership guards, two processes could write WAL/snapshots for the same shard and corrupt state.

### Key concepts

- `claim_ownership/2`
  - Writes shard metadata with a new epoch and current node.
  - Starts with `rehydrating: true`.
  - Meaning: "I am the latest owner, but recovery is still in progress."

- `owner_valid?/3`
  - Checks metadata still matches this process:
    - same `epoch`
    - same `owner_node`
    - `rehydrating == false`
  - Only valid owners can append WAL, rotate, snapshot, and finalize.
  - The shard caches this on ticks/transitions; **`CacheFlushEngine` uses that cache** for append/sync/snapshot gates so steady-state writes do not re-read `.meta` from disk on every op.

- `refresh_owner_validity/1`
  - Re-reads metadata and updates cached `owner_valid?` state.
  - Needed after metadata transitions and periodic ticks so stale processes stop writing quickly.

### Shard 10 walkthrough (realistic example)

Assume shard process `10` is running and storage is shared.

1. Node `node_a@cluster` starts shard `10`.
2. Existing metadata is:
   - `%{"epoch" => 4, "owner_node" => "node_b@cluster", "rehydrating" => false}`
3. `claim_ownership/2` writes:
   - `%{"epoch" => 5, "owner_node" => "node_a@cluster", "rehydrating" => true}`
4. Recovery loads snapshot + replays WAL into a temporary ETS table, registers the shard as **heir**, then exits so the shard receives `ETS-TRANSFER` and swaps that table in as the live ETS (no full `tab2list` copy).
5. `mark_rehydration_done/1` updates metadata:
   - `%{"epoch" => 5, "owner_node" => "node_a@cluster", "rehydrating" => false}`
6. `refresh_owner_validity/1` sets `owner_valid? = true`.
7. Writes proceed:
   - WAL append
   - ETS update
   - later snapshot/compaction.

### Failover case (why refresh matters)

Later, shard `10` is moved to `node_c@cluster`.

1. New process claims:
   - `%{"epoch" => 6, "owner_node" => "node_c@cluster", ...}`
2. Old process on `node_a@cluster` is now stale.
3. On next validity refresh tick, stale process sees metadata mismatch.
4. `owner_valid?` becomes `false`, and persistence operations are rejected (`:stale_owner`).

This prevents split-brain writes to the same shard files.

---

## Flush engine (`CachePuppyCore.Persistence.CacheFlushEngine`)

How WAL state and snapshot completion integrate with the shard.

### Quick flow

1. `CachePuppyCore.Persistence.CacheShardProcess` owns WAL state as a nested `%FlushState{}` struct.
2. Each `set` calls `CacheFlushEngine.persist_set/6` (with cached `owner_valid?`) before updating ETS.
3. The shard schedules `:flush_tick` to itself (`Process.send_after`); on each tick it calls `CacheFlushEngine.on_flush_tick/2` for sync, optional rotate, and snapshot eligibility.
4. Snapshot work runs under `Task.Supervisor.async_nolink` when a tick starts a snapshot; replay/`tab2file` stays off the shard’s synchronous `set` path.
5. After snapshot success, `on_snapshot_message/3` applies checkpoint + prune via `finalize_snapshot`.

### Overview

`CacheFlushEngine` is a **module** operating on an explicit `%FlushState{}` struct (WAL fd, segment seq, snapshot task ref, byte counters). The shard is the only production process that holds `%FlushState{}` and routes task messages; **flush tick timers** live on the shard, not on `%FlushState{}`.

### Public API (selected)

#### `open/2`

`open(shard_id, owner_epoch)`. Creates storage dir if needed, opens the latest WAL segment, returns `{:ok, %FlushState{}}`.

#### `close/1`

Syncs and closes the WAL fd on `%FlushState{}`.

#### `persist_set/6`

`persist_set(flush, owner_valid?, table, key, value, ttl_ms \\ nil)` — caller supplies cached `owner_valid?` (no per-write disk read), append, optional size-based rotate. Returns `{:ok, new_flush, ts_ms}` or `{:error, reason}`.

#### `on_flush_tick/2`

Runs periodic sync + rotate (when `owner_valid?` is true), then `maybe_start_snapshot` when allowed.

#### `on_snapshot_message/3`

Handles task completion tuples (`{:snapshot_done, ...}`) and updates flush state (checkpoint, prune, clear task ref).

#### `clear_snapshot_task_ref/1`

Clears `snapshot_task_ref` after a failed or abandoned snapshot task.

### Tests

Persistence behavior is covered under `test/cachepuppy_core/persistence/` (including `CacheShardProcess` integration tests and direct `CacheFlushEngine` calls where no GenServer mailbox is required, for example `persist_set/6` with a `%FlushState{}` from `open/2`).

### Related modules

- `CachePuppyCore.Persistence.CacheWalReplay` — WAL replay and snapshot materialization.
- `CachePuppyCore.Persistence.CacheRecoveryEngine` — startup recovery using `CacheWalReplay`.

---

## Recovery engine (`CachePuppyCore.Persistence.CacheRecoveryEngine`)

How startup recovery rebuilds in-memory state from snapshot + WAL.

### Quick flow

1. On shard startup, recovery tries loading the latest shard snapshot.
2. Recovery reads WAL checkpoint metadata to find where replay should begin.
3. Recovery lists WAL segment files for the shard and sorts them by segment sequence.
4. It replays WAL segments at/after checkpoint into ETS state.
5. If a WAL file ends with incomplete/corrupt trailing bytes, recovery applies only valid records.
6. Recovery truncates the invalid trailing tail so future startups are clean.
7. The recovered ETS table is returned to the shard process.

### Overview

`CacheRecoveryEngine` owns startup durability recovery:

- Load snapshot if available
- Replay WAL records after checkpoint
- Handle corrupted WAL tails safely

It does not append WAL entries, rotate segments, or trigger snapshots.

WAL decoding, replay, and tail truncation are delegated to `CachePuppyCore.Persistence.CacheWalReplay` so recovery matches snapshot materialization.

### Public functions

#### `load_snapshot_then_replay/2`

- Inputs:
  - `shard_id`
  - `storage_dir`
- Loads snapshot table or creates a new ETS table on cold start.
- Reads checkpoint sequence.
- Replays WAL segments newer than/equal to checkpoint sequence.
- Applies `CachePuppyCore.Persistence.CacheConfig.recovery_max_segments/0` as safety bound.
- Returns ETS table id.

#### `read_checkpoint_seq/2`

- Reads checkpoint file for shard.
- Extracts `snapshot_cutoff_seq`.
- Returns `1` when checkpoint is missing/invalid.

#### `truncate_corrupt_tail/1`

- Decodes length-prefixed WAL records from binary stream.
- Stops at first incomplete/corrupt tail boundary.
- Returns `{decoded_records, valid_bytes_consumed}`.

### Internal modules

#### `CachePuppyCore.Persistence.CacheUtils`

Provides shared path and WAL segment helpers used by both flush and recovery engines.

### Private functions (recovery)

#### `load_snapshot_or_new/2`

- Loads snapshot via `:ets.file2tab`.
- On failure creates fresh ETS table.
- Logs loaded vs cold-start path.

#### `replay_wal_file/2`

- Reads WAL bytes from file.
- Decodes valid records and applies supported ops (`:set`) into ETS.
- Truncates corrupt/incomplete trailing bytes when present.

#### `decode_records/3`

- Iteratively parses `<<length, payload>>` record format.
- Stops safely if remaining bytes are insufficient or payload decode fails.

#### `safe_binary_to_term/1`

- Decodes one term with rescue fallback.
- Returns `{:ok, term}` or `:error`.
