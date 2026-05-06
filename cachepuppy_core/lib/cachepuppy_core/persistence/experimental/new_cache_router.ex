defmodule CachePuppyCore.Persistence.Experimental.NewCacheRouter do
  @moduledoc false

  require Logger
  alias CachePuppyCore.Persistence.CacheConfig
  alias CachePuppyCore.Persistence.Experimental.NewCacheShardRead

  def setdata(table, key, value, opts \\ [])

  def setdata(table, key, value, opts)
      when is_binary(table) and is_binary(key) and is_list(opts) do
    with {:ok, shard_id} <- shard_id_for_entry(table, key),
         {:ok, pid} <- ensure_shard_started(shard_id),
         {:ok, owner_node} <- owner_node_for_pid(pid) do
      Logger.info(
        "cache_set route table=#{inspect(table)} key=#{inspect(key)} shard_id=#{shard_id} requested_by=#{node()} owner_node=#{owner_node}"
      )

      dispatch_set(owner_node, pid, shard_id, table, key, value, opts)
    end
  end

  def setdata(_table, _key, _value, _opts), do: {:error, :invalid_table_or_key}

  def getdata(table, key) when is_binary(table) and is_binary(key) do
    with {:ok, shard_id} <- shard_id_for_entry(table, key),
         {:ok, pid} <- ensure_shard_started(shard_id),
         {:ok, owner_node} <- owner_node_for_pid(pid) do
      Logger.info(
        "cache_get route table=#{inspect(table)} key=#{inspect(key)} shard_id=#{shard_id} requested_by=#{node()} owner_node=#{owner_node}"
      )

      dispatch_get(owner_node, pid, shard_id, table, key)
    end
  end

  def getdata(_table, _key), do: {:error, :invalid_table_or_key}

  def deldata(table, key) when is_binary(table) and is_binary(key) do
    with {:ok, shard_id} <- shard_id_for_entry(table, key),
         {:ok, pid} <- ensure_shard_started(shard_id),
         {:ok, owner_node} <- owner_node_for_pid(pid) do
      Logger.info(
        "cache_del route table=#{inspect(table)} key=#{inspect(key)} shard_id=#{shard_id} requested_by=#{node()} owner_node=#{owner_node}"
      )

      dispatch_delete(owner_node, pid, shard_id, table, key)
    end
  end

  def deldata(_table, _key), do: {:error, :invalid_table_or_key}

  def updatedata(table, key, patch, opts \\ [])

  def updatedata(table, key, patch, opts)
      when is_binary(table) and is_binary(key) and is_list(opts) do
    with {:ok, shard_id} <- shard_id_for_entry(table, key),
         {:ok, pid} <- ensure_shard_started(shard_id),
         {:ok, owner_node} <- owner_node_for_pid(pid) do
      Logger.info(
        "cache_update route table=#{inspect(table)} key=#{inspect(key)} shard_id=#{shard_id} requested_by=#{node()} owner_node=#{owner_node}"
      )

      dispatch_update(owner_node, pid, shard_id, table, key, patch, opts)
    end
  end

  def updatedata(_table, _key, _patch, _opts), do: {:error, :invalid_table_or_key}

  def shard_id_for_key(key) when is_binary(key) do
    shard_count = CacheConfig.shard_count()

    if shard_count > 0 do
      {:ok, :erlang.phash2(key, shard_count)}
    else
      {:error, :invalid_shard_count}
    end
  end

  def shard_id_for_entry(table, key) when is_binary(table) and is_binary(key) do
    shard_count = CacheConfig.shard_count()

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
    with {:ok, pid} <- ensure_shard_started(shard_id) do
      owner_node_for_pid(pid)
    end
  end

  def remote_setdata(pid, table, key, value, opts \\ []),
    do: call_shard(pid, {:set, table, key, value, opts})

  def remote_getdata(shard_id, table, key), do: NewCacheShardRead.fast_get(shard_id, table, key)

  def remote_deldata(pid, table, key), do: call_shard(pid, {:delete, table, key})

  def remote_updatedata(pid, table, key, patch, opts \\ []),
    do: call_shard(pid, {:update, table, key, patch, opts})

  defp dispatch_set(owner_node, pid, shard_id, table, key, value, opts)
       when owner_node == node() do
    Logger.info("cache_set local_execute shard_id=#{shard_id} node=#{node()}")
    call_shard(pid, {:set, table, key, value, opts})
  end

  defp dispatch_set(owner_node, pid, shard_id, table, key, value, opts) do
    rpc_timeout_ms = CacheConfig.rpc_timeout_ms()

    Logger.info(
      "cache_set rpc_execute shard_id=#{shard_id} from_node=#{node()} to_node=#{owner_node}"
    )

    try do
      :erpc.call(
        owner_node,
        __MODULE__,
        :remote_setdata,
        [pid, table, key, value, opts],
        rpc_timeout_ms
      )
    catch
      kind, reason ->
        Logger.warning(
          "cache_set rpc_failed shard_id=#{shard_id} from_node=#{node()} to_node=#{owner_node} kind=#{inspect(kind)} reason=#{inspect(reason)}"
        )

        {:error, {:rpc_failed, {kind, reason}}}
    end
  end

  defp dispatch_update(owner_node, pid, shard_id, table, key, patch, opts)
       when owner_node == node() do
    Logger.info("cache_update local_execute shard_id=#{shard_id} node=#{node()}")
    call_shard(pid, {:update, table, key, patch, opts})
  end

  defp dispatch_update(owner_node, pid, shard_id, table, key, patch, opts) do
    rpc_timeout_ms = CacheConfig.rpc_timeout_ms()

    Logger.info(
      "cache_update rpc_execute shard_id=#{shard_id} from_node=#{node()} to_node=#{owner_node}"
    )

    try do
      :erpc.call(
        owner_node,
        __MODULE__,
        :remote_updatedata,
        [pid, table, key, patch, opts],
        rpc_timeout_ms
      )
    catch
      kind, reason ->
        Logger.warning(
          "cache_update rpc_failed shard_id=#{shard_id} from_node=#{node()} to_node=#{owner_node} kind=#{inspect(kind)} reason=#{inspect(reason)}"
        )

        {:error, {:rpc_failed, {kind, reason}}}
    end
  end

  defp dispatch_delete(owner_node, pid, shard_id, table, key) when owner_node == node() do
    Logger.info("cache_del local_execute shard_id=#{shard_id} node=#{node()}")
    call_shard(pid, {:delete, table, key})
  end

  defp dispatch_delete(owner_node, pid, shard_id, table, key) do
    rpc_timeout_ms = CacheConfig.rpc_timeout_ms()

    Logger.info(
      "cache_del rpc_execute shard_id=#{shard_id} from_node=#{node()} to_node=#{owner_node}"
    )

    try do
      :erpc.call(owner_node, __MODULE__, :remote_deldata, [pid, table, key], rpc_timeout_ms)
    catch
      kind, reason ->
        Logger.warning(
          "cache_del rpc_failed shard_id=#{shard_id} from_node=#{node()} to_node=#{owner_node} kind=#{inspect(kind)} reason=#{inspect(reason)}"
        )

        {:error, {:rpc_failed, {kind, reason}}}
    end
  end

  defp dispatch_get(owner_node, _pid, shard_id, table, key) when owner_node == node() do
    Logger.info("cache_get local_execute shard_id=#{shard_id} node=#{node()}")
    NewCacheShardRead.fast_get(shard_id, table, key)
  end

  defp dispatch_get(owner_node, _pid, shard_id, table, key) do
    rpc_timeout_ms = CacheConfig.rpc_timeout_ms()

    Logger.info(
      "cache_get rpc_execute shard_id=#{shard_id} from_node=#{node()} to_node=#{owner_node}"
    )

    try do
      :erpc.call(owner_node, __MODULE__, :remote_getdata, [shard_id, table, key], rpc_timeout_ms)
    catch
      kind, reason ->
        Logger.warning(
          "cache_get rpc_failed shard_id=#{shard_id} from_node=#{node()} to_node=#{owner_node} kind=#{inspect(kind)} reason=#{inspect(reason)}"
        )

        {:error, {:rpc_failed, {kind, reason}}}
    end
  end

  defp call_shard(pid, message) do
    GenServer.call(pid, message)
  catch
    :exit, reason -> {:error, {:shard_unavailable, reason}}
  end

  defp start_shard(shard_id) do
    child_spec = CacheConfig.shard_process_opts(shard_id)

    case Horde.DynamicSupervisor.start_child(
           CachePuppyCore.CacheShardSupervisor,
           {CachePuppyCore.Persistence.Experimental.NewCacheShardProcess, child_spec}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, {:shard_start_failed, reason}}
    end
  end

  defp owner_node_for_pid(pid) when is_pid(pid) do
    {:ok, node(pid)}
  end
end
