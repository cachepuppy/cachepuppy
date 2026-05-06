# Persistence layer tests

These tests exercise the on-disk cache stack: routing to shards, per-shard memory and ownership, write-ahead logging, snapshots, recovery, and TTL cleanup.

They all use `CachePuppyCore.CachePersistenceCase` (see `test/support/cache_persistence_case.ex`). That case gives each test its own temporary storage directory, resets Horde-managed shard processes so tests do not leak into each other, and sets predictable application config (flush intervals, WAL size, shard count, and so on). Tests run with `async: false` so this shared setup stays safe.

Run everything in this folder:

```bash
cd cachepuppy_core && mix test test/cachepuppy_core/persistence/
```

---

## `cache_read_and_meta_test.exs`

**Modules:** `CacheShardRead`, `CacheOwnerMeta` (and `CacheEntry` for fixture data).

**What we check**

- **Rehydration vs ready:** While a shard is marked “rehydrating”, fast reads return `{:error, :rehydrating}`. After `publish_ready` with a small ETS table containing an entry, `fast_get` returns the stored value.
- **Ownership on disk:** Claiming ownership produces an epoch that is not valid until rehydration is marked done; after that, the same node and epoch are recognized as the owner.

**How:** Lightweight ETS tables and the real storage directory from the test case—no full shard GenServer unless implied by helpers.

---

## `cache_router_test.exs`

**Module:** `CacheRouter` (public API and related helpers like `ensure_shard_started`, shard id helpers, and `remote_*` calls).

**What we check**

- **Happy path:** Set, update, and delete a key through the router, with `CacheShardSync` used so the right shard is up and reads/writes line up.
- **Bad input:** Non-string table/key, wrong options types—router returns `{:error, :invalid_table_or_key}` (and similar) instead of crashing.
- **Shard lifecycle:** Starting the same shard twice returns a process; owner node for that shard is the current node.
- **Config edge case:** With `cache_shard_count` set to 0, shard id helpers return `{:error, :invalid_shard_count}`.
- **Remote API:** Direct `remote_setdata` / `remote_getdata` / `remote_updatedata` / `remote_deldata` on a known shard pid behave like the public contract.
- **Failure mapping:** If the shard process is terminated, remote calls return `{:error, {:shard_unavailable, _}}`.

**How:** Integration-style tests against the real router and Horde supervision, plus a small retry helper on `updatedata` when the shard is still warming (`:not_found`).

---

## `cache_shard_process_test.exs`

**Module:** `CacheShardProcess` (the per-shard GenServer).

**What we check**

- **Boot stability:** Many shards in a row start, become ready, and stay alive.
- **Rehydration:** Calling `rehydrate_sync` twice is fine; when ready, the ETS table is owned by the shard process.
- **Readiness gate:** If we force `ready?: false`, writes/updates/deletes return `{:error, :rehydrating}`.
- **Stale owner:** If something else claims ownership in storage, the shard stops accepting mutations and snapshots (`:stale_owner`) while keeping a consistent view of its epoch/table.
- **Mutation rules:** Invalid TTL, bad patches, update on missing keys, delete idempotence, scalar values that cannot be merged, TTL at configured max vs over max.
- **TTL behavior on update:** Omitting `ttl_ms` on update keeps an expiry in the future; updating an already-expired row returns `:not_found` without bringing it back.
- **Snapshot:** Allowed when the owner is still valid.
- **Shutdown cleanup:** Stopping the process clears its read-side metadata but does not remove unrelated shard meta published in the same test.

**How:** `start_supervised` for each shard, `:sys.get_state` / `replace_state` where we need to simulate internal flags, short sleeps only where the code under test is timer-driven or cross-process.

---

## `cache_shard_flush_process_test.exs`

**Module:** `CacheShardFlushProcess` (WAL batching and flushing).

**What we check**

- **Timer flush:** After enqueueing a write, the WAL on disk grows and the in-memory batch resets.
- **Batch size flush:** Enough enqueues in one go triggers an immediate flush (batch cleared, timer cleared).
- **Coalescing:** Several small writes can end up in a single segment without spawning extra segments after a short wait.
- **Rotation:** With a tiny max segment size, multiple WAL segments appear with ordered, unique sequence numbers.
- **Snapshot prep:** `prepare_snapshot` seals work, returns a sequence number, and pauses the flusher (no open WAL fd).
- **Empty tail:** Snapshot prep when the newest segment would be empty still returns a sensible included sequence vs existing files.
- **Pause queue:** While paused, enqueues pile up; `resume_after_snapshot` drains them and WAL shows data again.
- **Rehydration lifecycle:** `close_for_rehydration` is idempotent; close then `open_after_rehydration` allows writing again; missing storage directory surfaces `{:error, :enoent}` until the directory is recreated.

**How:** Supervised flush process per test, `CacheUtils.wal_segments/2` and file reads to observe disk, small polling helpers with bounded retries.

---

## `cache_shard_maintenance_process_test.exs`

**Module:** `CacheShardMaintenanceProcess` (checkpoints, WAL replay, pruning—often paired with `CacheShardFlushProcess`).

**What we check**

- **Snapshot + prune:** After enough WAL activity, `snapshot` writes a checkpoint whose cutoff sequence matches what remains on disk (older segments gone).
- **Bad checkpoint:** Corrupt checkpoint file falls back so `load_from_disk` can still rebuild state from the WAL.
- **Prune boundary:** At least one WAL segment remains at the cutoff sequence (nothing incorrectly deleted “past” the cutoff).
- **Replay ordering:** Multiple sets and a delete rebuild the expected ETS contents (last set wins, deleted key absent).
- **Recovery cap:** With `cache_recovery_max_segments` limited, only the earliest segment’s records are applied.
- **Corrupt WAL tail:** Garbage after a valid record is truncated on load; only the good record is visible.
- **Corrupt mid-stream:** A bad chunk between two records stops replay after the first good record; the file is truncated accordingly.
- **Repeatability:** Several snapshot → `load_from_disk` cycles stay consistent and produce valid checkpoint metadata.

**How:** Controlled WAL writes (sometimes hand-built binaries via `encode_record` in the test), flush process for realistic segments, then maintenance API calls and ETS/file assertions.

---

## `cache_shard_ttl_sweeper_test.exs`

**Module:** `CacheShardTtlSweeper` (invoked against a running shard).

**What we check**

- **Expiry cleanup:** A key with a 1 ms TTL is gone from fast reads after `run_once` on the sweeper, once time has passed.

**How:** Start a real `CacheShardProcess`, insert a short-TTL entry, sleep briefly, call `CacheShardTtlSweeper.run_once/1` with the shard’s sweeper pid, assert via `CacheShardRead.fast_get/3`.
