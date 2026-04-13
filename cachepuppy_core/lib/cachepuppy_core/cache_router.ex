defmodule CachePuppyCore.CacheRouter do
  @moduledoc false

  alias CachePuppyCore.CacheShardProcess
  require Logger

  @default_shard_count 64
  @default_ring_virtual_nodes 128
  @default_rpc_timeout_ms 5_000
  @default_flush_interval_ms 5_000
  @default_storage_dir "tmp/cache_shards"
  @ring_space 4_294_967_296

  def setdata(table, key, value) when is_binary(table) and is_binary(key) do
    with {:ok, shard_id} <- shard_id_for_entry(table, key),
         {:ok, owner_node} <- owner_node_for_shard(shard_id) do
      Logger.info(
        "cache_set route table=#{inspect(table)} key=#{inspect(key)} shard_id=#{shard_id} requested_by=#{node()} owner_node=#{owner_node}"
      )

      dispatch_set(owner_node, shard_id, table, key, value)
    end
  end

  def setdata(_table, _key, _value), do: {:error, :invalid_table_or_key}

  def getdata(table, key) when is_binary(table) and is_binary(key) do
    with {:ok, shard_id} <- shard_id_for_entry(table, key),
         {:ok, owner_node} <- owner_node_for_shard(shard_id) do
      Logger.info(
        "cache_get route table=#{inspect(table)} key=#{inspect(key)} shard_id=#{shard_id} requested_by=#{node()} owner_node=#{owner_node}"
      )

      dispatch_get(owner_node, shard_id, table, key)
    end
  end

  def getdata(_table, _key), do: {:error, :invalid_table_or_key}

  def shard_id_for_key(key) when is_binary(key) do
    shard_count = Application.get_env(:cachepuppy_core, :cache_shard_count, @default_shard_count)

    if shard_count > 0 do
      {:ok, :erlang.phash2(key, shard_count)}
    else
      {:error, :invalid_shard_count}
    end
  end

  def shard_id_for_entry(table, key) when is_binary(table) and is_binary(key) do
    shard_count = Application.get_env(:cachepuppy_core, :cache_shard_count, @default_shard_count)

    if shard_count > 0 do
      {:ok, :erlang.phash2({table, key}, shard_count)}
    else
      {:error, :invalid_shard_count}
    end
  end

  def ensure_shard_started(shard_id) when is_integer(shard_id) do
    case Horde.Registry.lookup(CachePuppyCore.CacheShardRegistry, shard_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        start_shard(shard_id)
    end
  end

  def owner_node_for_shard(shard_id) when is_integer(shard_id) do
    virtual_nodes =
      Application.get_env(
        :cachepuppy_core,
        :cache_ring_virtual_nodes,
        @default_ring_virtual_nodes
      )

    case owner_from_nodes(shard_id, cluster_nodes(), virtual_nodes) do
      nil -> {:error, :no_cluster_nodes}
      owner_node -> {:ok, owner_node}
    end
  end

  def owner_from_nodes(_shard_id, [], _virtual_nodes), do: nil

  def owner_from_nodes(shard_id, nodes, virtual_nodes)
      when is_integer(shard_id) and is_list(nodes) and is_integer(virtual_nodes) and
             virtual_nodes > 0 do
    ring =
      nodes
      |> Enum.uniq()
      |> Enum.sort()
      |> build_ring(virtual_nodes)

    key_hash = :erlang.phash2({:shard, shard_id}, @ring_space)

    ring
    |> Enum.find(fn {point, _node} -> point >= key_hash end)
    |> case do
      {_, owner_node} -> owner_node
      nil -> ring |> List.first() |> elem(1)
    end
  end

  def remote_setdata(shard_id, table, key, value) do
    with {:ok, _pid} <- ensure_shard_started(shard_id) do
      CacheShardProcess.set(shard_id, table, key, value)
    end
  end

  def remote_getdata(shard_id, table, key) do
    with {:ok, _pid} <- ensure_shard_started(shard_id) do
      CacheShardProcess.get(shard_id, table, key)
    end
  end

  defp dispatch_set(owner_node, shard_id, table, key, value) when owner_node == node() do
    Logger.info("cache_set local_execute shard_id=#{shard_id} node=#{node()}")

    with {:ok, _pid} <- ensure_shard_started(shard_id) do
      CacheShardProcess.set(shard_id, table, key, value)
    end
  end

  defp dispatch_set(owner_node, shard_id, table, key, value) do
    rpc_timeout_ms = Application.get_env(:cachepuppy_core, :cache_rpc_timeout_ms, @default_rpc_timeout_ms)
    Logger.info("cache_set rpc_execute shard_id=#{shard_id} from_node=#{node()} to_node=#{owner_node}")

    case :rpc.call(
           owner_node,
           __MODULE__,
           :remote_setdata,
           [shard_id, table, key, value],
           rpc_timeout_ms
         ) do
      {:badrpc, reason} -> {:error, {:rpc_failed, reason}}
      result -> result
    end
  end

  defp dispatch_get(owner_node, shard_id, table, key) when owner_node == node() do
    Logger.info("cache_get local_execute shard_id=#{shard_id} node=#{node()}")

    with {:ok, _pid} <- ensure_shard_started(shard_id) do
      CacheShardProcess.get(shard_id, table, key)
    end
  end

  defp dispatch_get(owner_node, shard_id, table, key) do
    rpc_timeout_ms = Application.get_env(:cachepuppy_core, :cache_rpc_timeout_ms, @default_rpc_timeout_ms)
    Logger.info("cache_get rpc_execute shard_id=#{shard_id} from_node=#{node()} to_node=#{owner_node}")

    case :rpc.call(owner_node, __MODULE__, :remote_getdata, [shard_id, table, key], rpc_timeout_ms) do
      {:badrpc, reason} -> {:error, {:rpc_failed, reason}}
      result -> result
    end
  end

  defp start_shard(shard_id) do
    child_spec = [
      shard_id: shard_id,
      flush_interval_ms:
        Application.get_env(:cachepuppy_core, :cache_flush_interval_ms, @default_flush_interval_ms),
      storage_dir: Application.get_env(:cachepuppy_core, :cache_storage_dir, @default_storage_dir)
    ]

    case Horde.DynamicSupervisor.start_child(
           CachePuppyCore.CacheShardSupervisor,
           {CacheShardProcess, child_spec}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, {:shard_start_failed, reason}}
    end
  end

  defp cluster_nodes do
    [node() | Node.list()]
    |> Enum.uniq()
  end

  defp build_ring(nodes, virtual_nodes) do
    points =
      for current_node <- nodes,
          vnode <- 0..(virtual_nodes - 1),
          do: {:erlang.phash2({current_node, vnode}, @ring_space), current_node}

    Enum.sort_by(points, fn {point, _node} -> point end)
  end
end
