defmodule CachePuppyCore.Persistence.CacheRecoveryEngineTest do
  use ExUnit.Case, async: false

  alias CachePuppyCore.Persistence.CacheRecoveryEngine
  alias CachePuppyCore.Persistence.CacheUtils

  test "load_snapshot_then_replay cold-starts when snapshot is missing" do
    shard_id = 21
    storage_dir = unique_storage_dir("cold_start")
    File.mkdir_p!(storage_dir)

    table = CacheRecoveryEngine.load_snapshot_then_replay(shard_id, storage_dir)
    assert :ets.info(table, :size) == 0
    :ets.delete(table)
  end

  test "load_snapshot_then_replay restores data from snapshot only" do
    shard_id = 22
    storage_dir = unique_storage_dir("snapshot_only")
    File.mkdir_p!(storage_dir)

    seed = :ets.new(:recovery_snapshot_only, [:set, :protected])
    true = :ets.insert(seed, {{"users", "name"}, "beamline"})

    :ok =
      :ets.tab2file(seed, String.to_charlist(CacheUtils.snapshot_path(storage_dir, shard_id)),
        sync: true
      )

    :ets.delete(seed)

    table = CacheRecoveryEngine.load_snapshot_then_replay(shard_id, storage_dir)
    assert [{{"users", "name"}, "beamline"}] = :ets.lookup(table, {"users", "name"})
    :ets.delete(table)
  end

  test "replays WAL records after snapshot checkpoint" do
    shard_id = 23
    storage_dir = unique_storage_dir("replay_after_checkpoint")
    File.mkdir_p!(storage_dir)

    seed = :ets.new(:recovery_checkpoint_seed, [:set, :protected])
    true = :ets.insert(seed, {{"users", "base"}, "v0"})

    :ok =
      :ets.tab2file(seed, String.to_charlist(CacheUtils.snapshot_path(storage_dir, shard_id)),
        sync: true
      )

    :ets.delete(seed)

    checkpoint = %{
      "snapshot_cutoff_seq" => 2,
      "updated_at_ms" => System.system_time(:millisecond)
    }

    File.write!(
      CacheUtils.checkpoint_path(storage_dir, shard_id),
      :erlang.term_to_binary(checkpoint)
    )

    File.write!(
      CacheUtils.wal_path(storage_dir, shard_id, 1),
      encode_record({:set, "users", "old", "x", 1})
    )

    File.write!(
      CacheUtils.wal_path(storage_dir, shard_id, 2),
      encode_record({:set, "users", "new", "y", 2})
    )

    table = CacheRecoveryEngine.load_snapshot_then_replay(shard_id, storage_dir)
    assert [] = :ets.lookup(table, {"users", "old"})
    assert [{{"users", "new"}, "y"}] = :ets.lookup(table, {"users", "new"})
    :ets.delete(table)
  end

  test "read_checkpoint_seq returns 1 when missing" do
    assert CacheRecoveryEngine.read_checkpoint_seq(unique_storage_dir("missing_checkpoint"), 24) ==
             1
  end

  test "read_checkpoint_seq returns 1 when invalid checkpoint data" do
    shard_id = 25
    storage_dir = unique_storage_dir("invalid_checkpoint")
    File.mkdir_p!(storage_dir)
    File.write!(CacheUtils.checkpoint_path(storage_dir, shard_id), "garbage")
    assert CacheRecoveryEngine.read_checkpoint_seq(storage_dir, shard_id) == 1
  end

  test "read_checkpoint_seq returns stored sequence when valid" do
    shard_id = 26
    storage_dir = unique_storage_dir("valid_checkpoint")
    File.mkdir_p!(storage_dir)

    File.write!(
      CacheUtils.checkpoint_path(storage_dir, shard_id),
      :erlang.term_to_binary(%{"snapshot_cutoff_seq" => 9, "updated_at_ms" => 1})
    )

    assert CacheRecoveryEngine.read_checkpoint_seq(storage_dir, shard_id) == 9
  end

  test "truncate_corrupt_tail returns valid records and consumed bytes" do
    record1 = encode_record({:set, "users", "k1", "v1", 1})
    record2 = encode_record({:set, "users", "k2", "v2", 2})
    binary = record1 <> record2 <> <<1, 2, 3>>

    {records, consumed} = CacheRecoveryEngine.truncate_corrupt_tail(binary)
    assert length(records) == 2
    assert consumed == byte_size(record1) + byte_size(record2)
  end

  test "replay truncates corrupted trailing bytes in WAL file" do
    shard_id = 27
    storage_dir = unique_storage_dir("truncate_tail")
    File.mkdir_p!(storage_dir)

    wal_path = CacheUtils.wal_path(storage_dir, shard_id, 1)
    File.write!(wal_path, encode_record({:set, "users", "k1", "v1", 1}) <> <<1, 2, 3>>)
    size_before = File.stat!(wal_path).size

    table = CacheRecoveryEngine.load_snapshot_then_replay(shard_id, storage_dir)
    assert [{{"users", "k1"}, "v1"}] = :ets.lookup(table, {"users", "k1"})
    :ets.delete(table)

    size_after = File.stat!(wal_path).size
    assert size_after < size_before
  end

  test "load_snapshot_then_replay applies recovery_max_segments limit" do
    shard_id = 28
    storage_dir = unique_storage_dir("recovery_limit")
    File.mkdir_p!(storage_dir)

    with_recovery_limit(1, fn ->
      File.write!(
        CacheUtils.wal_path(storage_dir, shard_id, 1),
        encode_record({:set, "users", "k", "v1", 1})
      )

      File.write!(
        CacheUtils.wal_path(storage_dir, shard_id, 2),
        encode_record({:set, "users", "k", "v2", 2})
      )

      table = CacheRecoveryEngine.load_snapshot_then_replay(shard_id, storage_dir)
      assert [{{"users", "k"}, "v1"}] = :ets.lookup(table, {"users", "k"})
      :ets.delete(table)
    end)
  end

  test "wal replay follows segment ordering" do
    shard_id = 29
    storage_dir = unique_storage_dir("ordering")
    File.mkdir_p!(storage_dir)

    File.write!(
      CacheUtils.wal_path(storage_dir, shard_id, 2),
      encode_record({:set, "users", "k", "v2", 2})
    )

    File.write!(
      CacheUtils.wal_path(storage_dir, shard_id, 1),
      encode_record({:set, "users", "k", "v1", 1})
    )

    table = CacheRecoveryEngine.load_snapshot_then_replay(shard_id, storage_dir)
    assert [{{"users", "k"}, "v2"}] = :ets.lookup(table, {"users", "k"})
    :ets.delete(table)
  end

  test "replay ignores unsupported operation records" do
    shard_id = 30
    storage_dir = unique_storage_dir("unsupported_op")
    File.mkdir_p!(storage_dir)

    File.write!(
      CacheUtils.wal_path(storage_dir, shard_id, 1),
      encode_record({:delete, "users", "k", 1})
    )

    table = CacheRecoveryEngine.load_snapshot_then_replay(shard_id, storage_dir)
    assert [] = :ets.lookup(table, {"users", "k"})
    :ets.delete(table)
  end

  defp with_recovery_limit(limit, fun) do
    old = Application.get_env(:cachepuppy_core, :cache_recovery_max_segments)
    Application.put_env(:cachepuppy_core, :cache_recovery_max_segments, limit)

    try do
      fun.()
    after
      if old == nil do
        Application.delete_env(:cachepuppy_core, :cache_recovery_max_segments)
      else
        Application.put_env(:cachepuppy_core, :cache_recovery_max_segments, old)
      end
    end
  end

  defp encode_record(term) do
    payload = :erlang.term_to_binary(term)
    <<byte_size(payload)::unsigned-integer-size(32), payload::binary>>
  end

  defp unique_storage_dir(label) do
    Path.join(
      System.tmp_dir!(),
      "cache_recovery_engine_#{label}_#{System.unique_integer([:positive])}"
    )
  end
end
