defmodule ShardBench.ShardServer do
  @moduledoc false
  use GenServer

  @table_name :shard_bench_ets

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def set(server, key, value) do
    GenServer.call(server, {:set, key, value}, :infinity)
  end

  def table_name, do: @table_name

  @impl true
  def init(:ok) do
    _ =
      :ets.new(@table_name, [
        :set,
        :named_table,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, %{writes: 0}}
  end

  @impl true
  def handle_call({:set, key, value}, _from, state) do
    true = :ets.insert(@table_name, {key, value})
    {:reply, :ok, %{state | writes: state.writes + 1}}
  end
end

defmodule ShardBench do
  @moduledoc false

  @ops_per_task 1_000
  @concurrency_levels [10, 50, 100, 500, 1_000]
  @summary_table :shard_bench_summary

  def run do
    {:ok, shard_pid} = ShardBench.ShardServer.start_link(name: :shard_bench_server)
    :ets.new(@summary_table, [:named_table, :public, :set])

    inputs = Map.new(@concurrency_levels, &{"#{&1}", &1})

    Benchee.run(
      %{
        "single_shard_sync_set" => fn concurrency ->
          run_round(shard_pid, concurrency)
        end
      },
      inputs: inputs,
      warmup: 2,
      time: 10
    )

    print_summary()
    print_interpretation_notes()
  end

  defp run_round(shard_pid, concurrency) do
    parent = self()
    run_ref = make_ref()
    peak_mailbox = start_mailbox_sampler(shard_pid, parent, run_ref)

    tasks =
      for task_id <- 1..concurrency do
        Task.async(fn ->
          receive do
            {:start, ^run_ref} -> :ok
          end

          perform_sets(shard_pid, task_id)
        end)
      end

    started_at_native = System.monotonic_time()
    Enum.each(tasks, &send(&1.pid, {:start, run_ref}))

    all_latencies_us =
      tasks
      |> Enum.flat_map(fn task ->
        Task.await(task, :infinity)
      end)

    elapsed_us = System.convert_time_unit(System.monotonic_time() - started_at_native, :native, :microsecond)
    elapsed_s = elapsed_us / 1_000_000
    total_ops = concurrency * @ops_per_task
    ops_per_sec = total_ops / elapsed_s

    send(peak_mailbox, {:stop, run_ref})

    peak_depth =
      receive do
        {:mailbox_peak, ^run_ref, depth} -> depth
      after
        5_000 -> -1
      end

    p50 = percentile(all_latencies_us, 0.50)
    p95 = percentile(all_latencies_us, 0.95)
    p99 = percentile(all_latencies_us, 0.99)

    update_summary(concurrency, ops_per_sec, p50, p95, p99, peak_depth)

    # Benchee measures invocation runtime; return value is not used by Benchee.
    :ok
  end

  defp perform_sets(shard_pid, task_id) do
    Enum.map(1..@ops_per_task, fn iteration ->
      key = {task_id, iteration, System.unique_integer([:positive, :monotonic])}
      value = iteration
      started_at = System.monotonic_time()
      :ok = ShardBench.ShardServer.set(shard_pid, key, value)
      System.convert_time_unit(System.monotonic_time() - started_at, :native, :microsecond)
    end)
  end

  defp start_mailbox_sampler(shard_pid, parent, run_ref) do
    spawn(fn -> sample_mailbox_loop(shard_pid, parent, run_ref, 0) end)
  end

  defp sample_mailbox_loop(shard_pid, parent, run_ref, peak_so_far) do
    current_depth =
      case Process.info(shard_pid, :message_queue_len) do
        {:message_queue_len, len} -> len
        _ -> 0
      end

    next_peak = max(peak_so_far, current_depth)

    receive do
      {:stop, ^run_ref} ->
        send(parent, {:mailbox_peak, run_ref, next_peak})
    after
      5 ->
        sample_mailbox_loop(shard_pid, parent, run_ref, next_peak)
    end
  end

  defp percentile([], _quantile), do: 0

  defp percentile(samples, quantile) do
    sorted = Enum.sort(samples)
    last_index = length(sorted) - 1
    index = floor(last_index * quantile)
    Enum.at(sorted, index)
  end

  defp update_summary(concurrency, ops_per_sec, p50, p95, p99, peak_depth) do
    case :ets.lookup(@summary_table, concurrency) do
      [] ->
        :ets.insert(@summary_table, {concurrency, 1, ops_per_sec, p50, p95, p99, peak_depth})

      [{^concurrency, runs, ops_sum, p50_sum, p95_sum, p99_sum, peak_max}] ->
        :ets.insert(
          @summary_table,
          {concurrency, runs + 1, ops_sum + ops_per_sec, p50_sum + p50, p95_sum + p95, p99_sum + p99, max(peak_max, peak_depth)}
        )
    end
  end

  defp print_summary do
    rows =
      @concurrency_levels
      |> Enum.map(fn concurrency ->
        case :ets.lookup(@summary_table, concurrency) do
          [{^concurrency, runs, ops_sum, _p50_sum, _p95_sum, p99_sum, peak_max}] ->
            avg_ops = ops_sum / runs
            avg_p99_us = p99_sum / runs
            {concurrency, avg_ops, avg_p99_us, peak_max}

          _ ->
            {concurrency, 0.0, 0.0, 0}
        end
      end)

    IO.puts("")
    IO.puts("ETS Single-Shard GenServer SET Throughput")
    IO.puts(String.duplicate("-", 78))
    IO.puts(String.pad_trailing("concurrency", 16) <> String.pad_trailing("ops/sec", 20) <> String.pad_trailing("p99 latency (us)", 22) <> "peak mailbox depth")
    IO.puts(String.duplicate("-", 78))

    Enum.each(rows, fn {concurrency, ops, p99, peak} ->
      IO.puts(
        String.pad_trailing(Integer.to_string(concurrency), 16) <>
          String.pad_trailing(:erlang.float_to_binary(ops, decimals: 2), 20) <>
          String.pad_trailing(:erlang.float_to_binary(p99, decimals: 2), 22) <>
          Integer.to_string(peak)
      )
    end)

    IO.puts(String.duplicate("-", 78))
  end

  defp print_interpretation_notes do
    IO.puts("""

    Notes:
    - p99 latency shows tail behavior for synchronous calls. When p99 rises sharply while ops/sec
      plateaus, the shard is at or near its single-process service ceiling.
    - Peak mailbox depth is backlog pressure. If it grows and stays high at higher concurrency,
      callers are enqueueing faster than this shard can drain requests.
    - A practical sharding trigger is sustained high p99 plus growing mailbox depth under expected
      production concurrency. Add shards to split write load before these tails become user-visible.
    """)
  end
end

ShardBench.run()
