# ETS Single-Shard GenServer Benchmark

This benchmark measures write throughput and tail latency for one GenServer shard that accepts synchronous `GenServer.call/3` `SET` requests and writes to ETS.

The script:

- starts one shard process
- creates one ETS table in `init/1` with `:public` and `:named_table`
- runs caller concurrency at `10`, `50`, `100`, `500`, and `1000`
- performs `1000` synchronous `SET` calls per task
- measures per concurrency level:
  - average `ops/sec`
  - average `p99` latency per call (microseconds)
  - peak shard mailbox depth seen during each run
- executes with Benchee warmup/run settings:
  - warmup: `2s`
  - benchmark time: `10s`

## Run

From the `cachepuppy_core` root:

```bash
mix deps.get
mix run bench/shard_bench.exs
```

## Output

At the end, the script prints a compact summary table:

```
concurrency | ops/sec | p99 latency (us) | peak mailbox depth
```

You should generally see:

- lower concurrency: higher throughput scaling, low mailbox depth, tighter p99
- higher concurrency: throughput starts to flatten, p99 increases, mailbox depth rises

## How to interpret shard ceiling

- **p99 latency** tells you how bad tail waits get for the slowest 1% of synchronous callers.
- **peak mailbox depth** tells you queue pressure inside the single GenServer process.

When throughput plateaus while p99 and mailbox depth rise, the shard is likely saturated. That is your signal to add more shards and distribute keys/writes across them to reduce queueing delay.
