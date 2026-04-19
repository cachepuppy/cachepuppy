defmodule CachePuppyCore.Persistence.CacheShardProcess do
  @moduledoc false

  use GenServer
  require Logger
  alias CachePuppyCore.Persistence.CacheConfig
  alias CachePuppyCore.Persistence.CacheEntry
  alias CachePuppyCore.Persistence.CacheShardRead
  alias CachePuppyCore.Persistence.CacheShardTtlSweeper
  alias CachePuppyCore.Persistence.CacheFlushEngine
  alias CachePuppyCore.Persistence.CacheFlushEngine.FlushState
  alias CachePuppyCore.Persistence.CacheOwnerMeta
  alias CachePuppyCore.Persistence.CacheRecoveryEngine

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            shard_id: non_neg_integer(),
            table: :ets.tid(),
            owner_epoch: non_neg_integer(),
            ready?: boolean(),
            owner_valid?: boolean(),
            flush: %FlushState{},
            flush_tick_ref: reference() | nil,
            recovery_task_ref: reference() | nil,
            owner_check_ref: reference() | nil,
            ttl_sweeper_pid: pid() | nil
          }

    defstruct shard_id: 0,
              table: nil,
              owner_epoch: 0,
              ready?: false,
              owner_valid?: false,
              flush: nil,
              flush_tick_ref: nil,
              recovery_task_ref: nil,
              owner_check_ref: nil,
              ttl_sweeper_pid: nil
  end

  def child_spec(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)

    %{
      id: {__MODULE__, shard_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def start_link(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)
    name = Keyword.get(opts, :name, via_shard(shard_id))

    case name do
      nil -> GenServer.start_link(__MODULE__, opts)
      _ -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  def set(shard_id, table, key, value, opts \\ []) when is_integer(shard_id) and is_list(opts) do
    GenServer.call(via_shard(shard_id), {:set, table, key, value, opts})
  end

  def delete(shard_id, table, key) when is_integer(shard_id) do
    GenServer.call(via_shard(shard_id), {:delete, table, key})
  end

  @impl true
  def init(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)
    storage_dir = CacheConfig.storage_dir()

    _ = File.mkdir_p(storage_dir)
    owner_epoch = CacheOwnerMeta.claim_ownership(storage_dir, shard_id, to_string(node()))
    table = :ets.new(__MODULE__, [:set, :protected])
    CacheShardRead.publish_rehydrating(shard_id, table, owner_epoch)

    {:ok, flush} = CacheFlushEngine.open(shard_id, owner_epoch)

    owner_valid? =
      CacheOwnerMeta.owner_valid?(storage_dir, shard_id, owner_epoch, to_string(node()))

    ref = make_ref()
    caller = self()

    _pid =
      spawn(fn ->
        try do
          recovered = CacheRecoveryEngine.load_snapshot_then_replay(shard_id, storage_dir)

          case :ets.setopts(recovered, {:heir, caller, ref}) do
            true ->
              :ok

            false ->
              send(caller, {:recovery_done, ref, {:error, :ets_heir_setopts_failed}})
          end
        rescue
          error -> send(caller, {:recovery_done, ref, {:error, error}})
        end
      end)

    state = %State{
      shard_id: shard_id,
      table: table,
      owner_epoch: owner_epoch,
      ready?: false,
      owner_valid?: owner_valid?,
      flush: flush,
      recovery_task_ref: ref
    }

    state = schedule_flush_tick(state)

    {:ok, sweeper} = CacheShardTtlSweeper.start_link(shard_id: shard_id, owner: self())
    true = Process.link(sweeper)
    state = %{state | ttl_sweeper_pid: sweeper}

    Logger.info(
      "cache_shard init shard_id=#{shard_id} node=#{node()} owner_epoch=#{owner_epoch} owner_valid=#{owner_valid?} ready=false storage_dir=#{storage_dir}"
    )

    {:ok, schedule_owner_check(state)}
  end

  @impl true
  def handle_call({:set, table, key, value}, from, state)
      when is_binary(table) and is_binary(key) do
    handle_call({:set, table, key, value, []}, from, state)
  end

  def handle_call({:set, table, key, value, opts}, _from, state)
      when is_binary(table) and is_binary(key) and is_list(opts) do
    ttl_ms = Keyword.get(opts, :ttl_ms)

    cond do
      not state.ready? ->
        {:reply, {:error, :rehydrating}, state}

      not state.owner_valid? ->
        {:reply, {:error, :stale_owner}, state}

      not (ttl_ms == nil or (is_integer(ttl_ms) and ttl_ms > 0)) ->
        {:reply, {:error, :invalid_ttl}, state}

      true ->
        storage_key = {table, key}

        case CacheFlushEngine.persist_set(
               state.flush,
               state.owner_valid?,
               table,
               key,
               value,
               ttl_ms
             ) do
          {:ok, new_flush, wal_ts_ms} ->
            entry = CacheEntry.from_wal(value, wal_ts_ms, ttl_ms)
            :ets.insert(state.table, {storage_key, entry})

            Logger.debug(
              "cache_set execute shard_id=#{state.shard_id} node=#{node()} table=#{inspect(table)} key=#{inspect(key)}"
            )

            {:reply, {:ok, value}, %{state | flush: new_flush}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:set, _table, _key, _value, _opts}, _from, state) do
    {:reply, {:error, :invalid_table_or_key}, state}
  end

  def handle_call({:delete, table, key}, _from, state)
      when is_binary(table) and is_binary(key) do
    cond do
      not state.ready? ->
        {:reply, {:error, :rehydrating}, state}

      not state.owner_valid? ->
        {:reply, {:error, :stale_owner}, state}

      true ->
        storage_key = {table, key}

        if :ets.member(state.table, storage_key) do
          case CacheFlushEngine.persist_delete(state.flush, state.owner_valid?, table, key) do
            {:ok, new_flush} ->
              :ets.delete(state.table, storage_key)
              {:reply, {:ok, true}, %{state | flush: new_flush}}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        else
          {:reply, {:ok, false}, state}
        end
    end
  end

  def handle_call({:delete, _table, _key}, _from, state) do
    {:reply, {:error, :invalid_table_or_key}, state}
  end

  @impl true
  def handle_info(
        {:"ETS-TRANSFER", recovered_tid, _from, ref},
        %State{recovery_task_ref: ref, table: old_table} = state
      ) do
    :ets.delete(old_table)

    state = %{
      state
      | table: recovered_tid,
        recovery_task_ref: nil,
        ready?: true
    }

    state = mark_rehydration_done(state)
    state = refresh_owner_validity(state)
    CacheShardRead.publish_ready(state.shard_id, state.table, state.owner_epoch)

    recovered_size = :ets.info(recovered_tid, :size)

    Logger.info(
      "cache_shard ready shard_id=#{state.shard_id} node=#{node()} recovered_entries=#{recovered_size}"
    )

    {:noreply, state}
  end

  def handle_info({:recovery_done, ref, {:error, reason}}, %State{recovery_task_ref: ref} = state) do
    Logger.warning(
      "cache_rehydrate failed shard_id=#{state.shard_id} node=#{node()} reason=#{inspect(reason)}"
    )

    CacheShardRead.publish_rehydrating(state.shard_id, state.table, state.owner_epoch)
    {:noreply, %{state | recovery_task_ref: nil, ready?: false}}
  end

  def handle_info(:flush_tick, state) do
    flush = CacheFlushEngine.on_flush_tick(state.flush, state.owner_valid?)
    state = %{state | flush: flush} |> schedule_flush_tick()

    {:noreply, state}
  end

  def handle_info({ref, reply}, %State{flush: %FlushState{snapshot_task_ref: ref}} = state)
      when is_reference(ref) do
    _ = Process.demonitor(ref, [:flush])

    flush =
      CacheFlushEngine.on_snapshot_message(state.flush, reply, state.owner_valid?)

    {:noreply, %{state | flush: flush}}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %State{flush: %FlushState{snapshot_task_ref: ref}} = state
      )
      when is_reference(ref) do
    Logger.warning(
      "cache_snapshot task_down shard_id=#{state.shard_id} node=#{node()} reason=#{inspect(reason)}"
    )

    {:noreply, %{state | flush: CacheFlushEngine.clear_snapshot_task_ref(state.flush)}}
  end

  def handle_info(:owner_check_tick, state) do
    state = %{state | owner_check_ref: nil}
    {:noreply, schedule_owner_check(refresh_owner_validity(state))}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    CacheShardRead.clear(self())

    state = cancel_flush_tick(state)
    _ = CacheFlushEngine.close(state.flush)

    :ok
  end

  defp mark_rehydration_done(%State{shard_id: shard_id, owner_epoch: epoch} = state) do
    storage_dir = CacheConfig.storage_dir()
    _ = CacheOwnerMeta.mark_rehydration_done(storage_dir, shard_id, epoch, to_string(node()))

    state
  end

  defp owner_valid?(storage_dir, shard_id, epoch) do
    CacheOwnerMeta.owner_valid?(storage_dir, shard_id, epoch, to_string(node()))
  end

  defp refresh_owner_validity(%State{shard_id: shard_id, owner_epoch: epoch} = state) do
    storage_dir = CacheConfig.storage_dir()
    %{state | owner_valid?: owner_valid?(storage_dir, shard_id, epoch)}
  end

  defp schedule_owner_check(state) do
    ref = Process.send_after(self(), :owner_check_tick, CacheConfig.flush_interval_ms())
    %{state | owner_check_ref: ref}
  end

  defp schedule_flush_tick(state) do
    ref = Process.send_after(self(), :flush_tick, CacheConfig.flush_interval_ms())
    %{state | flush_tick_ref: ref}
  end

  defp cancel_flush_tick(%State{flush_tick_ref: nil} = s), do: s

  defp cancel_flush_tick(%State{flush_tick_ref: ref} = s) do
    Process.cancel_timer(ref)
    %{s | flush_tick_ref: nil}
  end

  defp via_shard(shard_id) do
    {:via, Horde.Registry, {CachePuppyCore.CacheShardRegistry, shard_id}}
  end
end
