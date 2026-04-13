defmodule CachePuppyCore.CacheShardProcessTest do
  use ExUnit.Case, async: true

  alias CachePuppyCore.CacheShardProcess

  test "rehydrates from snapshot file on startup" do
    shard_id = 7
    storage_dir = unique_storage_dir("rehydrate")
    snapshot = Path.join(storage_dir, "shard_#{shard_id}.ets")
    meta = Path.join(storage_dir, "shard_#{shard_id}.meta")
    File.mkdir_p!(storage_dir)

    table = :ets.new(:rehydrate_seed, [:set, :protected])
    true = :ets.insert(table, {"name", "beamline"})
    :ok = :ets.tab2file(table, String.to_charlist(snapshot), sync: true)
    :ets.delete(table)
    File.write!(meta, :erlang.term_to_binary(%{"epoch" => 1, "owner_node" => "seed", "rehydrating" => false}))

    pid =
      start_supervised!({
        CacheShardProcess,
        shard_id: shard_id,
        flush_interval_ms: 1_000,
        storage_dir: storage_dir,
        name: nil
      })

    _ = :sys.get_state(pid)
    assert {:ok, "beamline"} = GenServer.call(pid, {:get, "name"})
  end

  test "flush_tick writes only when shard is dirty" do
    shard_id = 9
    storage_dir = unique_storage_dir("flush")
    snapshot = Path.join(storage_dir, "shard_#{shard_id}.ets")

    pid =
      start_supervised!({
        CacheShardProcess,
        shard_id: shard_id,
        flush_interval_ms: 10_000,
        storage_dir: storage_dir,
        name: nil
      })

    send(pid, :flush_tick)
    _ = :sys.get_state(pid)
    refute File.exists?(snapshot)

    assert {:ok, 42} = GenServer.call(pid, {:set, "answer", 42})
    send(pid, :flush_tick)
    _ = :sys.get_state(pid)
    assert File.exists?(snapshot)

    assert {:ok, restored} = :ets.file2tab(String.to_charlist(snapshot))
    assert [{"answer", 42}] = :ets.lookup(restored, "answer")
    :ets.delete(restored)
  end

  test "flush is skipped when metadata owner/epoch no longer matches process" do
    shard_id = 12
    storage_dir = unique_storage_dir("stale_owner")
    snapshot = Path.join(storage_dir, "shard_#{shard_id}.ets")
    metadata = Path.join(storage_dir, "shard_#{shard_id}.meta")

    pid =
      start_supervised!({
        CacheShardProcess,
        shard_id: shard_id,
        flush_interval_ms: 10_000,
        storage_dir: storage_dir,
        name: nil
      })

    assert {:ok, "value"} = GenServer.call(pid, {:set, "key", "value"})

    stale_meta = %{
      "epoch" => 999,
      "owner_node" => "other@node",
      "rehydrating" => false,
      "updated_at_ms" => System.system_time(:millisecond)
    }

    File.write!(metadata, :erlang.term_to_binary(stale_meta))

    send(pid, :flush_tick)
    _ = :sys.get_state(pid)
    refute File.exists?(snapshot)
  end

  defp unique_storage_dir(label) do
    Path.join(System.tmp_dir!(), "cache_shard_process_#{label}_#{System.unique_integer([:positive])}")
  end
end
