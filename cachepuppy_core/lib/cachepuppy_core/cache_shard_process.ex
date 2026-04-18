defmodule CachePuppyCore.CacheShardProcess do
  @moduledoc false

  use GenServer
  require Logger
  alias CachePuppyCore.CacheConfig
  alias CachePuppyCore.CacheShardRead
  alias CachePuppyCore.Persistence.CacheFlushEngine
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
            flush_pid: pid() | nil,
            recovery_task_ref: reference() | nil,
            owner_check_ref: reference() | nil
          }

    defstruct shard_id: 0,
              table: nil,
              owner_epoch: 0,
              ready?: false,
              owner_valid?: false,
              flush_pid: nil,
              recovery_task_ref: nil,
              owner_check_ref: nil
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

  def set(shard_id, table, key, value) when is_integer(shard_id) do
    GenServer.call(via_shard(shard_id), {:set, table, key, value})
  end

  @impl true
  def init(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)
    snapshot_interval_ms = CacheConfig.snapshot_interval_ms()
    snapshot_min_wal_bytes = CacheConfig.snapshot_min_wal_bytes()
    storage_dir = CacheConfig.storage_dir()

    _ = File.mkdir_p(storage_dir)
    owner_epoch = CacheOwnerMeta.claim_ownership(storage_dir, shard_id, to_string(node()))
    table = :ets.new(__MODULE__, [:set, :protected])
    CacheShardRead.publish_rehydrating(shard_id, table, owner_epoch)

    {:ok, flush_pid} =
      CacheFlushEngine.start_link(
        shard_id: shard_id,
        table: table,
        owner_epoch: owner_epoch,
        snapshot_interval_ms: snapshot_interval_ms,
        snapshot_min_wal_bytes: snapshot_min_wal_bytes
      )

    owner_valid? =
      CacheOwnerMeta.owner_valid?(storage_dir, shard_id, owner_epoch, to_string(node()))

    ref = make_ref()
    caller = self()

    _pid =
      spawn(fn ->
        try do
          recovered = CacheRecoveryEngine.load_snapshot_then_replay(shard_id, storage_dir)
          entries = :ets.tab2list(recovered)
          :ets.delete(recovered)
          send(caller, {:recovery_done, ref, {:ok, entries}})
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
      flush_pid: flush_pid,
      recovery_task_ref: ref
    }

    Logger.info(
      "cache_shard init shard_id=#{shard_id} node=#{node()} owner_epoch=#{owner_epoch} owner_valid=#{owner_valid?} ready=false storage_dir=#{storage_dir}"
    )

    {:ok, schedule_owner_check(state)}
  end

  @impl true
  def handle_call({:set, table, key, value}, _from, state)
      when is_binary(table) and is_binary(key) do
    cond do
      not state.ready? ->
        {:reply, {:error, :rehydrating}, state}

      not state.owner_valid? ->
        {:reply, {:error, :stale_owner}, state}

      true ->
        storage_key = {table, key}

        case CacheFlushEngine.persist_set(state.flush_pid, table, key, value) do
          :ok ->
            :ets.insert(state.table, {storage_key, value})

            Logger.debug(
              "cache_set execute shard_id=#{state.shard_id} node=#{node()} table=#{inspect(table)} key=#{inspect(key)}"
            )

            {:reply, {:ok, value}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:set, _table, _key, _value}, _from, state) do
    {:reply, {:error, :invalid_table_or_key}, state}
  end

  @impl true
  def handle_info({:recovery_done, ref, {:ok, entries}}, %State{recovery_task_ref: ref} = state) do
    if entries != [] do
      :ets.insert(state.table, entries)
    end

    state = mark_rehydration_done(state)
    state = refresh_owner_validity(%{state | recovery_task_ref: nil, ready?: true})
    CacheShardRead.publish_ready(state.shard_id, state.table, state.owner_epoch)

    Logger.info(
      "cache_shard ready shard_id=#{state.shard_id} node=#{node()} recovered_entries=#{length(entries)}"
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

  def handle_info(:owner_check_tick, state) do
    state = %{state | owner_check_ref: nil}
    {:noreply, schedule_owner_check(refresh_owner_validity(state))}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %State{flush_pid: flush_pid}) do
    CacheShardRead.clear(self())
    if is_pid(flush_pid), do: Process.exit(flush_pid, :normal)
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

  defp via_shard(shard_id) do
    {:via, Horde.Registry, {CachePuppyCore.CacheShardRegistry, shard_id}}
  end
end
