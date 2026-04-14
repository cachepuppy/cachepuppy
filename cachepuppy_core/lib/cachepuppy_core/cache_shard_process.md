# Cache Shard Process

This document explains why shard ownership is claimed, validated, and refreshed in `CacheShardProcess`.

## Why this exists

Shard processes can move between nodes (failover/rebalance), while persistence files are shared.  
Without ownership guards, two processes could write WAL/snapshots for the same shard and corrupt state.

## Key concepts

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

- `refresh_owner_validity/1`
  - Re-reads metadata and updates cached `owner_valid?` state.
  - Needed after metadata transitions and periodic ticks so stale processes stop writing quickly.

## Shard 10 walkthrough (realistic example)

Assume shard process `10` is running and storage is shared.

1. Node `node_a@cluster` starts shard `10`.
2. Existing metadata is:
   - `%{"epoch" => 4, "owner_node" => "node_b@cluster", "rehydrating" => false}`
3. `claim_ownership/2` writes:
   - `%{"epoch" => 5, "owner_node" => "node_a@cluster", "rehydrating" => true}`
4. Recovery loads snapshot + replays WAL.
5. `mark_rehydration_done/1` updates metadata:
   - `%{"epoch" => 5, "owner_node" => "node_a@cluster", "rehydrating" => false}`
6. `refresh_owner_validity/1` sets `owner_valid? = true`.
7. Writes proceed:
   - WAL append
   - ETS update
   - later snapshot/compaction.

## Failover case (why refresh matters)

Later, shard `10` is moved to `node_c@cluster`.

1. New process claims:
   - `%{"epoch" => 6, "owner_node" => "node_c@cluster", ...}`
2. Old process on `node_a@cluster` is now stale.
3. On next validity refresh tick, stale process sees metadata mismatch.
4. `owner_valid?` becomes `false`, and persistence operations are rejected (`:stale_owner`).

This prevents split-brain writes to the same shard files.
