# Cache Recovery Engine

This document explains each function in `CachePuppyCore.Persistence.CacheRecoveryEngine` and how recovery works.

## Quick Flow (Gist First)

1. On shard startup, recovery tries loading the latest shard snapshot.
2. Recovery reads WAL checkpoint metadata to find where replay should begin.
3. Recovery lists WAL segment files for the shard and sorts them by segment sequence.
4. It replays WAL segments at/after checkpoint into ETS state.
5. If a WAL file ends with incomplete/corrupt trailing bytes, recovery applies only valid records.
6. Recovery truncates the invalid trailing tail so future startups are clean.
7. The recovered ETS table is returned to the shard process.

## Overview

`CacheRecoveryEngine` owns startup durability recovery:
- Load snapshot if available
- Replay WAL records after checkpoint
- Handle corrupted WAL tails safely

It does not append WAL entries, rotate segments, or trigger snapshots.

WAL decoding, replay, and tail truncation are delegated to `CachePuppyCore.Persistence.CacheWalReplay` so recovery matches snapshot materialization.

## Public Functions

### `load_snapshot_then_replay/2`
- Inputs:
  - `shard_id`
  - `storage_dir`
- Loads snapshot table or creates a new ETS table on cold start.
- Reads checkpoint sequence.
- Replays WAL segments newer than/equal to checkpoint sequence.
- Applies `CacheConfig.recovery_max_segments/0` as safety bound.
- Returns ETS table id.

### `read_checkpoint_seq/2`
- Reads checkpoint file for shard.
- Extracts `snapshot_cutoff_seq`.
- Returns `1` when checkpoint is missing/invalid.

### `truncate_corrupt_tail/1`
- Decodes length-prefixed WAL records from binary stream.
- Stops at first incomplete/corrupt tail boundary.
- Returns `{decoded_records, valid_bytes_consumed}`.

## Internal Modules

### `CachePuppyCore.Persistence.CacheUtils`
- Provides shared path and WAL segment helpers used by both flush and recovery engines.

## Private Functions

### `load_snapshot_or_new/2`
- Loads snapshot via `:ets.file2tab`.
- On failure creates fresh ETS table.
- Logs loaded vs cold-start path.

### `replay_wal_file/2`
- Reads WAL bytes from file.
- Decodes valid records and applies supported ops (`:set`) into ETS.
- Truncates corrupt/incomplete trailing bytes when present.

### `decode_records/3`
- Iteratively parses `<<length, payload>>` record format.
- Stops safely if remaining bytes are insufficient or payload decode fails.

### `safe_binary_to_term/1`
- Decodes one term with rescue fallback.
- Returns `{:ok, term}` or `:error`.
