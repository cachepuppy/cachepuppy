defmodule CachePuppyCore.Persistence.Experimental.NewCacheReadAndMetaTest do
  use CachePuppyCore.ExperimentalPersistenceCase, async: false

  alias CachePuppyCore.Persistence.Experimental.NewCacheEntry
  alias CachePuppyCore.Persistence.Experimental.NewCacheOwnerMeta
  alias CachePuppyCore.Persistence.Experimental.NewCacheShardRead

  test "fast_get reports rehydrating before ready" do
    tid = :ets.new(__MODULE__, [:set, :protected])
    :ok = NewCacheShardRead.publish_rehydrating(42, tid, 1)
    assert {:error, :rehydrating} = NewCacheShardRead.fast_get(42, "t", "k")
    :ok = NewCacheShardRead.clear(self())
  end

  test "publish_ready enables lookup" do
    tid = :ets.new(__MODULE__, [:set, :protected])
    :ets.insert(tid, {{"t", "k"}, %NewCacheEntry{value: 9, expires_at_ms: nil}})

    :ok = NewCacheShardRead.publish_ready(43, tid, 1)
    assert {:ok, 9} = NewCacheShardRead.fast_get(43, "t", "k")
    :ok = NewCacheShardRead.clear(self())
  end

  test "owner meta claim and mark rehydration done", %{storage_dir: storage_dir} do
    epoch = NewCacheOwnerMeta.claim_ownership(storage_dir, 55, "node")
    refute NewCacheOwnerMeta.owner_valid?(storage_dir, 55, epoch, "node")

    :ok = NewCacheOwnerMeta.mark_rehydration_done(storage_dir, 55, epoch, "node")
    assert NewCacheOwnerMeta.owner_valid?(storage_dir, 55, epoch, "node")
    assert NewCacheOwnerMeta.claim_holder?(storage_dir, 55, epoch, "node")
  end
end
