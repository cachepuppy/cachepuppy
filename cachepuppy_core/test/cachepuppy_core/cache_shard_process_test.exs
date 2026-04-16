defmodule CachePuppyCore.CacheShardProcessTest do
  use ExUnit.Case, async: false

  alias CachePuppyCore.Persistence.CacheFlushEngine
  alias CachePuppyCore.Persistence.CacheUtils
  alias CachePuppyCore.CacheShardRead
  alias CachePuppyCore.CacheShardProcess

  test "rehydrates from snapshot and WAL on startup" do
    shard_id = 7
    storage_dir = unique_storage_dir("rehydrate")
    meta = Path.join(storage_dir, "shard_#{shard_id}.meta")

    with_cache_config(storage_dir, 1024, 1_000, fn ->
      File.mkdir_p!(storage_dir)

      table = :ets.new(:rehydrate_seed, [:set, :protected])
      true = :ets.insert(table, {{"users", "name"}, "beamline"})
      snapshot_path = CacheUtils.snapshot_path(storage_dir, shard_id)
      snapshot_tmp = CacheUtils.snapshot_temp_path(storage_dir, shard_id)
      :ok = :ets.tab2file(table, String.to_charlist(snapshot_tmp), sync: true)
      :ok = File.rename(snapshot_tmp, snapshot_path)
      :ets.delete(table)

      File.write!(
        meta,
        :erlang.term_to_binary(%{
          "epoch" => 1,
          "owner_node" => to_string(node()),
          "rehydrating" => false
        })
      )

      flush_pid =
        start_supervised!(
          {CacheFlushEngine,
           shard_id: shard_id,
           table: :ets.new(:rehydrate_flush, [:set, :protected]),
           owner_epoch: 1,
           snapshot_interval_ms: 60_000,
           snapshot_min_wal_bytes: 1_000}
        )

      CacheFlushEngine.persist_set(flush_pid, "users", "city", "blr")
      _ = :sys.get_state(flush_pid)

      pid = start_supervised!({CacheShardProcess, shard_id: shard_id, name: nil})
      wait_until_ready(pid)
      assert {:ok, "beamline"} = CacheShardRead.fast_get(shard_id, "users", "name")
      assert {:ok, "blr"} = CacheShardRead.fast_get(shard_id, "users", "city")
    end)
  end

  test "set appends WAL record for shard" do
    shard_id = 9
    storage_dir = unique_storage_dir("wal")

    with_cache_config(storage_dir, 1_048_576, 100_000, fn ->
      pid = start_supervised!({CacheShardProcess, shard_id: shard_id, name: nil})
      wait_until_ready(pid)
      assert {:ok, 42} = GenServer.call(pid, {:set, "users", "answer", 42})
      flush_pid = :sys.get_state(pid).flush_pid
      _ = :sys.get_state(flush_pid)

      wal_files =
        storage_dir
        |> File.ls!()
        |> Enum.filter(&String.starts_with?(&1, "shard_#{shard_id}.wal."))

      assert wal_files != []
      wal_path = Path.join(storage_dir, hd(wal_files))
      assert File.stat!(wal_path).size > 0
    end)
  end

  test "set is rejected after periodic ownership revalidation detects stale metadata" do
    shard_id = 12
    storage_dir = unique_storage_dir("stale_owner")
    metadata = Path.join(storage_dir, "shard_#{shard_id}.meta")

    with_cache_config(storage_dir, 1_048_576, 10_000, fn ->
      pid = start_supervised!({CacheShardProcess, shard_id: shard_id, name: nil})
      wait_until_ready(pid)

      stale_meta = %{
        "epoch" => 999,
        "owner_node" => "other@node",
        "rehydrating" => false,
        "updated_at_ms" => System.system_time(:millisecond)
      }

      File.write!(metadata, :erlang.term_to_binary(stale_meta))

      send(pid, :owner_check_tick)
      _ = :sys.get_state(pid)
      assert {:error, :stale_owner} = GenServer.call(pid, {:set, "users", "key", "value"})
    end)
  end

  defp with_cache_config(storage_dir, wal_segment_max_bytes, flush_interval_ms, fun) do
    old_storage = Application.get_env(:cachepuppy_core, :cache_storage_dir)
    old_wal_bytes = Application.get_env(:cachepuppy_core, :cache_wal_segment_max_bytes)
    old_flush = Application.get_env(:cachepuppy_core, :cache_flush_interval_ms)

    Application.put_env(:cachepuppy_core, :cache_storage_dir, storage_dir)
    Application.put_env(:cachepuppy_core, :cache_wal_segment_max_bytes, wal_segment_max_bytes)
    Application.put_env(:cachepuppy_core, :cache_flush_interval_ms, flush_interval_ms)

    try do
      fun.()
    after
      restore_env(:cache_storage_dir, old_storage)
      restore_env(:cache_wal_segment_max_bytes, old_wal_bytes)
      restore_env(:cache_flush_interval_ms, old_flush)
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:cachepuppy_core, key)
  defp restore_env(key, value), do: Application.put_env(:cachepuppy_core, key, value)

  defp unique_storage_dir(label) do
    Path.join(
      System.tmp_dir!(),
      "cache_shard_process_#{label}_#{System.unique_integer([:positive])}"
    )
  end

  defp wait_until_ready(pid, attempts \\ 200)
  defp wait_until_ready(_pid, 0), do: flunk("shard did not become ready in time")

  defp wait_until_ready(pid, attempts) do
    state = :sys.get_state(pid)

    if state.ready? do
      :ok
    else
      receive do
      after
        10 -> wait_until_ready(pid, attempts - 1)
      end
    end
  end
end
