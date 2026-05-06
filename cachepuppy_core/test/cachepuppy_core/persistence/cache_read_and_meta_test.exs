defmodule CachePuppyCore.Persistence.CacheReadAndMetaTest do
  use CachePuppyCore.CachePersistenceCase, async: false

  alias CachePuppyCore.Persistence.CacheEntry
  alias CachePuppyCore.Persistence.CacheOwnerMeta
  alias CachePuppyCore.Persistence.CacheShardRead

  test "fast_get reports rehydrating before ready" do
    tid = :ets.new(__MODULE__, [:set, :protected])
    :ok = CacheShardRead.publish_rehydrating(42, tid, 1)
    assert {:error, :rehydrating} = CacheShardRead.fast_get(42, "t", "k")
    :ok = CacheShardRead.clear(self())
  end

  test "publish_ready enables lookup" do
    tid = :ets.new(__MODULE__, [:set, :protected])
    :ets.insert(tid, {{"t", "k"}, %CacheEntry{value: 9, expires_at_ms: nil}})

    :ok = CacheShardRead.publish_ready(43, tid, 1)
    assert {:ok, 9} = CacheShardRead.fast_get(43, "t", "k")
    :ok = CacheShardRead.clear(self())
  end

  test "owner meta claim and mark rehydration done", %{storage_dir: storage_dir} do
    epoch = CacheOwnerMeta.claim_ownership(storage_dir, 55, "node")
    refute CacheOwnerMeta.owner_valid?(storage_dir, 55, epoch, "node")

    :ok = CacheOwnerMeta.mark_rehydration_done(storage_dir, 55, epoch, "node")
    assert CacheOwnerMeta.owner_valid?(storage_dir, 55, epoch, "node")
    assert CacheOwnerMeta.claim_holder?(storage_dir, 55, epoch, "node")
  end
end
