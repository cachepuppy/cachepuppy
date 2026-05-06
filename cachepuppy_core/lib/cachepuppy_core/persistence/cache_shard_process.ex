defmodule CachePuppyCore.Persistence.CacheShardProcess do
  @moduledoc """
  Experimental ETS-first cache shard: mutations update ETS then enqueue async WAL
  batches via `CacheShardFlushProcess`. Rehydration and snapshot run in
  `CacheShardMaintenanceProcess`.

  Starts linked flush + maintenance in `init/1`, then continues with
  `:startup_rehydrate` to load snapshot + WAL from disk (no extra supervisor).

  Does not register with Horde; use for experiments only.
  """

  use GenServer

  alias CachePuppyCore.Persistence.CacheConfig
  alias CachePuppyCore.Persistence.CacheEntry
  alias CachePuppyCore.Persistence.CacheOwnerMeta
  alias CachePuppyCore.Persistence.CacheShardRead
  alias CachePuppyCore.Persistence.CacheShardFlushProcess
  alias CachePuppyCore.Persistence.CacheShardMaintenanceProcess
  alias CachePuppyCore.Persistence.CacheShardTtlSweeper

  defmodule State do
    @moduledoc false
    defstruct [
      :shard_id,
      :table,
      :owner_epoch,
      :ready?,
      :owner_valid?,
      :flush_pid,
      :maintenance_pid,
      :owner_check_ref,
      :ttl_sweeper_pid
    ]
  end

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :shard_id)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  @impl true
  def init(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)
    storage_dir = CacheConfig.storage_dir()
    _ = File.mkdir_p(storage_dir)

    owner_epoch = CacheOwnerMeta.claim_ownership(storage_dir, shard_id, to_string(node()))
    table = :ets.new(__MODULE__, [:set, :protected])
    :ok = CacheShardRead.publish_rehydrating(shard_id, table, owner_epoch)

    {:ok, flush_pid} = CacheShardFlushProcess.start_link(shard_id: shard_id)
    true = Process.link(flush_pid)

    {:ok, maintenance_pid} =
      CacheShardMaintenanceProcess.start_link(shard_id: shard_id, flush_pid: flush_pid)

    true = Process.link(maintenance_pid)

    {:ok, sweeper} = CacheShardTtlSweeper.start_link(shard_id: shard_id, owner: self())
    true = Process.link(sweeper)

    owner_valid? =
      CacheOwnerMeta.owner_valid?(storage_dir, shard_id, owner_epoch, to_string(node()))

    state = %State{
      shard_id: shard_id,
      table: table,
      owner_epoch: owner_epoch,
      ready?: false,
      owner_valid?: owner_valid?,
      flush_pid: flush_pid,
      maintenance_pid: maintenance_pid,
      owner_check_ref: nil,
      ttl_sweeper_pid: sweeper
    }

    state = schedule_owner_check(state)
    {:ok, state, {:continue, :startup_rehydrate}}
  end

  @impl true
  def handle_continue(:startup_rehydrate, state) do
    case run_rehydration(state) do
      {:ok, st} -> {:noreply, st}
      {:error, reason} -> {:stop, reason, state}
    end
  end

  @impl true
  def handle_call(:rehydrate_sync, _from, state) do
    case run_rehydration(state) do
      {:ok, st} -> {:reply, :ok, st}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    if not state.owner_valid? do
      {:reply, {:error, :stale_owner}, state}
    else
      reply = CacheShardMaintenanceProcess.snapshot(state.maintenance_pid)
      {:reply, reply, state}
    end
  end

  @impl true
  def handle_call({:set, table, key, value, opts}, _from, state)
      when is_binary(table) and is_binary(key) and is_list(opts) do
    ttl_ms = Keyword.get(opts, :ttl_ms)

    with :ok <- deny_unless_ready(state),
         :ok <- ttl_ok(ttl_ms),
         :ok <- deny_unless_owner(state) do
      ts_ms = System.system_time(:millisecond)
      storage_key = {table, key}
      entry = CacheEntry.from_wal(value, ts_ms, ttl_ms)
      :ets.insert(state.table, {storage_key, entry})

      CacheShardFlushProcess.enqueue(
        state.flush_pid,
        {:set, table, key, value, ts_ms, ttl_ms}
      )

      {:reply, {:ok, value}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:delete, table, key}, _from, state)
      when is_binary(table) and is_binary(key) do
    with :ok <- deny_unless_ready(state),
         :ok <- deny_unless_owner(state) do
      storage_key = {table, key}

      if :ets.member(state.table, storage_key) do
        ts_ms = System.system_time(:millisecond)
        :ets.delete(state.table, storage_key)
        CacheShardFlushProcess.enqueue(state.flush_pid, {:delete, table, key, ts_ms})
        {:reply, {:ok, true}, state}
      else
        {:reply, {:ok, false}, state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:update, table, key, patch, opts}, _from, state)
      when is_binary(table) and is_binary(key) and is_list(opts) do
    ttl_ms_opt = Keyword.get(opts, :ttl_ms)

    with :ok <- deny_unless_ready(state),
         :ok <- map_patch_or_error(patch),
         :ok <- ttl_ok(ttl_ms_opt),
         :ok <- deny_unless_owner(state) do
      storage_key = {table, key}
      now_ms = System.system_time(:millisecond)

      case :ets.lookup(state.table, storage_key) do
        [] ->
          {:reply, {:error, :not_found}, state}

        [{^storage_key, %CacheEntry{} = entry}] ->
          cond do
            cache_entry_expired?(entry, now_ms) ->
              {:reply, {:error, :not_found}, state}

            not is_map(entry.value) ->
              {:reply, {:error, :value_not_mergeable}, state}

            true ->
              merged = Map.merge(entry.value, patch)

              persist_ttl_ms =
                case ttl_ms_opt do
                  nil ->
                    case entry.expires_at_ms do
                      nil -> nil
                      exp when is_integer(exp) -> max(1, exp - now_ms)
                    end

                  t ->
                    t
                end

              ts_ms = System.system_time(:millisecond)
              new_entry = CacheEntry.from_wal(merged, ts_ms, persist_ttl_ms)
              :ets.insert(state.table, {storage_key, new_entry})

              CacheShardFlushProcess.enqueue(
                state.flush_pid,
                {:set, table, key, merged, ts_ms, persist_ttl_ms}
              )

              {:reply, {:ok, merged}, state}
          end
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:owner_check_tick, state) do
    state = %{state | owner_check_ref: nil}
    {:noreply, schedule_owner_check(refresh_owner_validity(state))}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, _state) do
    _ = CacheShardRead.clear(self())
    :ok
  end

  defp deny_unless_ready(%State{ready?: true}), do: :ok
  defp deny_unless_ready(_), do: {:error, :rehydrating}

  defp deny_unless_owner(%State{owner_valid?: true}), do: :ok
  defp deny_unless_owner(_), do: {:error, :stale_owner}

  defp ttl_ok(nil), do: :ok

  defp ttl_ok(ms) when is_integer(ms) and ms > 0 do
    if ms <= CacheConfig.ttl_ms_max(), do: :ok, else: {:error, :invalid_ttl}
  end

  defp ttl_ok(_), do: {:error, :invalid_ttl}

  defp map_patch_or_error(patch) when is_map(patch), do: :ok
  defp map_patch_or_error(_), do: {:error, :invalid_patch}

  defp run_rehydration(state) do
    case CacheShardMaintenanceProcess.load_from_disk(state.maintenance_pid) do
      {:ok, table} ->
        finalize_rehydration(state, table)

      {:error, :enoent} ->
        # Storage paths can vanish during churn; recover as cold start instead of crashing.
        table = :ets.new(__MODULE__, [:set, :protected])
        finalize_rehydration(state, table)

      {:error, _} = err ->
        err
    end
  end

  defp finalize_rehydration(state, table) do
    state = swap_table_internal(state, table)

    case CacheShardFlushProcess.open_after_rehydration(state.flush_pid) do
      :ok ->
        {:ok, state}

      {:error, :enoent} ->
        :ok = File.mkdir_p(CacheConfig.storage_dir())

        case CacheShardFlushProcess.open_after_rehydration(state.flush_pid) do
          :ok -> {:ok, state}
          {:error, _} = err -> err
        end

      {:error, _} = err ->
        err
    end
  end

  defp swap_table_internal(%State{} = state, recovered_tid) do
    owned_tid = adopt_recovered_table(recovered_tid)

    # Rehydrate tables are built in maintenance process; old table may not be owned here.
    _ = safe_delete_table(state.table)

    storage_dir = CacheConfig.storage_dir()

    _ =
      CacheOwnerMeta.mark_rehydration_done(
        storage_dir,
        state.shard_id,
        state.owner_epoch,
        to_string(node())
      )

    :ok = CacheShardRead.publish_ready(state.shard_id, owned_tid, state.owner_epoch)

    state
    |> Map.replace!(:table, owned_tid)
    |> Map.replace!(:ready?, true)
    |> refresh_owner_validity()
  end

  defp adopt_recovered_table(source_tid) do
    target = :ets.new(__MODULE__, [:set, :protected])

    :ets.tab2list(source_tid)
    |> Enum.each(fn row -> :ets.insert(target, row) end)

    _ = safe_delete_table(source_tid)
    target
  end

  defp safe_delete_table(tid) do
    try do
      :ets.delete(tid)
    catch
      :error, :badarg -> :ok
    end
  end

  defp refresh_owner_validity(%State{shard_id: sid, owner_epoch: epoch} = state) do
    storage_dir = CacheConfig.storage_dir()
    valid? = CacheOwnerMeta.owner_valid?(storage_dir, sid, epoch, to_string(node()))
    %State{state | owner_valid?: valid?}
  end

  defp schedule_owner_check(%State{} = state) do
    ref = Process.send_after(self(), :owner_check_tick, CacheConfig.flush_interval_ms())
    %State{state | owner_check_ref: ref}
  end

  defp cache_entry_expired?(%CacheEntry{expires_at_ms: nil}, _now_ms), do: false

  defp cache_entry_expired?(%CacheEntry{expires_at_ms: exp}, now_ms)
       when is_integer(exp) and is_integer(now_ms),
       do: exp <= now_ms
end
