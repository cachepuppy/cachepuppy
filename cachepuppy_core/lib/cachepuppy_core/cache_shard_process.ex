defmodule CachePuppyCore.CacheShardProcess do
  @moduledoc false

  use GenServer
  require Logger
  alias CachePuppyCore.CacheConfig
  alias CachePuppyCore.Persistence.CacheFlushEngine
  alias CachePuppyCore.Persistence.CacheRecoveryEngine

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            shard_id: non_neg_integer(),
            table: :ets.tid(),
            flush_interval_ms: non_neg_integer(),
            snapshot_interval_ms: non_neg_integer(),
            snapshot_min_wal_bytes: non_neg_integer(),
            owner_epoch: non_neg_integer(),
            owner_valid?: boolean(),
            flush_ref: reference() | nil,
            snapshot_task_ref: reference() | nil,
            flush_engine: CachePuppyCore.Persistence.CacheFlushEngine.t()
          }

    defstruct shard_id: 0,
              table: nil,
              flush_interval_ms: 5_000,
              snapshot_interval_ms: 60_000,
              snapshot_min_wal_bytes: 262_144,
              owner_epoch: 0,
              owner_valid?: false,
              flush_ref: nil,
              snapshot_task_ref: nil,
              flush_engine: nil
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

  def get(shard_id, table, key) when is_integer(shard_id) do
    GenServer.call(via_shard(shard_id), {:get, table, key})
  end

  @impl true
  def init(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)
    flush_interval_ms = CacheConfig.flush_interval_ms()
    snapshot_interval_ms = CacheConfig.snapshot_interval_ms()
    snapshot_min_wal_bytes = CacheConfig.snapshot_min_wal_bytes()
    storage_dir = CacheConfig.storage_dir()

    _ = File.mkdir_p(storage_dir)
    owner_epoch = claim_ownership(shard_id, storage_dir)
    table = CacheRecoveryEngine.load_snapshot_then_replay(shard_id, storage_dir)

    {:ok, flush_engine} = CacheFlushEngine.init(shard_id: shard_id)

    owner_valid? = owner_valid?(storage_dir, shard_id, owner_epoch)

    state = %State{
      shard_id: shard_id,
      table: table,
      flush_interval_ms: flush_interval_ms,
      snapshot_interval_ms: snapshot_interval_ms,
      snapshot_min_wal_bytes: snapshot_min_wal_bytes,
      owner_epoch: owner_epoch,
      owner_valid?: owner_valid?,
      flush_engine: flush_engine
    }

    mark_rehydration_done(state)
    state = refresh_owner_validity(state)

    Logger.info(
      "cache_shard init shard_id=#{shard_id} node=#{node()} owner_epoch=#{owner_epoch} owner_valid=#{owner_valid?} storage_dir=#{storage_dir}"
    )

    {:ok, schedule_flush(state)}
  end

  @impl true
  def handle_call({:set, table, key, value}, _from, state)
      when is_binary(table) and is_binary(key) do
    case persist_and_apply_set(state, table, key, value) do
      {:ok, next_state} ->
        Logger.debug(
          "cache_set execute shard_id=#{state.shard_id} node=#{node()} table=#{inspect(table)} key=#{inspect(key)}"
        )

        {:reply, {:ok, value}, next_state}

      {:error, :stale_owner, next_state} ->
        {:reply, {:error, :stale_owner}, next_state}

      {:error, :wal_write_failed, next_state} ->
        {:reply, {:error, :wal_write_failed}, next_state}
    end
  end

  def handle_call({:set, _table, _key, _value}, _from, state) do
    {:reply, {:error, :invalid_table_or_key}, state}
  end

  @impl true
  def handle_call({:get, table, key}, _from, state) when is_binary(table) and is_binary(key) do
    storage_key = {table, key}

    value =
      case :ets.lookup(state.table, storage_key) do
        [{^storage_key, found}] -> found
        [] -> nil
      end

    Logger.debug(
      "cache_get execute shard_id=#{state.shard_id} node=#{node()} table=#{inspect(table)} key=#{inspect(key)}"
    )

    {:reply, {:ok, value}, state}
  end

  def handle_call({:get, _table, _key}, _from, state) do
    {:reply, {:error, :invalid_table_or_key}, state}
  end

  @impl true
  def handle_info(:flush_tick, state) do
    state = %{state | flush_ref: nil}
    state = refresh_owner_validity(state)
    state = maybe_maintenance(state)
    state = maybe_start_snapshot(state)
    {:noreply, schedule_flush(state)}
  end

  def handle_info(
        {:snapshot_done, ref, result, cutoff_seq},
        %State{snapshot_task_ref: ref} = state
      ) do
    {:noreply, handle_snapshot_done(state, result, cutoff_seq)}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %State{flush_engine: engine}) do
    _ = CacheFlushEngine.close(engine)
    :ok
  end

  defp maybe_maintenance(state) do
    if state.owner_valid? do
      with {:ok, engine} <- CacheFlushEngine.maybe_sync(state.flush_engine),
           {:ok, engine} <- CacheFlushEngine.maybe_rotate(engine) do
        %{state | flush_engine: engine}
      else
        {:error, reason} ->
          Logger.warning(
            "cache_flush_maintenance failed shard_id=#{state.shard_id} node=#{node()} reason=#{inspect(reason)}"
          )

          state
      end
    else
      state
    end
  end

  defp maybe_start_snapshot(%State{snapshot_task_ref: ref} = state) when not is_nil(ref),
    do: state

  defp maybe_start_snapshot(state) do
    if state.owner_valid? and
         CacheFlushEngine.should_snapshot?(
           state.flush_engine,
           state.snapshot_interval_ms,
           state.snapshot_min_wal_bytes
         ) do
      engine = CacheFlushEngine.mark_snapshot_started(state.flush_engine)
      cutoff_seq = CacheFlushEngine.snapshot_cutoff_seq(engine)
      caller = self()
      table = state.table
      shard_id = state.shard_id

      ref = make_ref()

      _pid =
        spawn(fn ->
          result = CacheFlushEngine.write_snapshot(table, shard_id)
          send(caller, {:snapshot_done, ref, result, cutoff_seq})
        end)

      %{state | flush_engine: engine, snapshot_task_ref: ref}
    else
      state
    end
  end

  defp handle_snapshot_done(state, :ok, cutoff_seq) do
    if state.owner_valid? do
      {:ok, engine} = CacheFlushEngine.finalize_snapshot(state.flush_engine, cutoff_seq)

      Logger.info(
        "cache_snapshot success shard_id=#{state.shard_id} node=#{node()} cutoff_seq=#{cutoff_seq}"
      )

      %{state | flush_engine: engine, snapshot_task_ref: nil}
    else
      %{state | snapshot_task_ref: nil}
    end
  end

  defp handle_snapshot_done(state, {:error, reason}, _cutoff_seq) do
    Logger.warning(
      "cache_snapshot failed shard_id=#{state.shard_id} node=#{node()} reason=#{inspect(reason)}"
    )

    %{state | snapshot_task_ref: nil}
  end

  defp persist_and_apply_set(state, table, key, value) do
    if state.owner_valid? do
      with {:ok, engine} <- CacheFlushEngine.append_set(state.flush_engine, table, key, value),
           {:ok, engine} <- CacheFlushEngine.maybe_rotate(engine) do
        storage_key = {table, key}
        :ets.insert(state.table, {storage_key, value})
        {:ok, %{state | flush_engine: engine}}
      else
        {:error, reason} ->
          Logger.warning(
            "cache_set wal_failed shard_id=#{state.shard_id} node=#{node()} reason=#{inspect(reason)}"
          )

          {:error, :wal_write_failed, state}
      end
    else
      {:error, :stale_owner, state}
    end
  end

  defp claim_ownership(shard_id, storage_dir) do
    meta = read_meta(storage_dir, shard_id)
    epoch = Map.get(meta, "epoch", 0) + 1
    persisted = base_meta(epoch, true)
    write_meta!(storage_dir, shard_id, persisted)
    epoch
  end

  defp mark_rehydration_done(%State{
         shard_id: shard_id,
         owner_epoch: epoch
       }) do
    storage_dir = CacheConfig.storage_dir()
    meta = read_meta(storage_dir, shard_id)

    if Map.get(meta, "epoch") == epoch and Map.get(meta, "owner_node") == to_string(node()) do
      write_meta!(storage_dir, shard_id, base_meta(epoch, false))
    end
  end

  defp owner_valid?(storage_dir, shard_id, epoch) do
    meta = read_meta(storage_dir, shard_id)

    Map.get(meta, "epoch") == epoch and
      Map.get(meta, "owner_node") == to_string(node()) and
      Map.get(meta, "rehydrating") == false
  end

  defp refresh_owner_validity(%State{shard_id: shard_id, owner_epoch: epoch} = state) do
    storage_dir = CacheConfig.storage_dir()
    %{state | owner_valid?: owner_valid?(storage_dir, shard_id, epoch)}
  end

  defp base_meta(epoch, rehydrating) do
    %{
      "epoch" => epoch,
      "owner_node" => to_string(node()),
      "rehydrating" => rehydrating,
      "updated_at_ms" => System.system_time(:millisecond)
    }
  end

  defp read_meta(storage_dir, shard_id) do
    path = metadata_path(storage_dir, shard_id)

    case File.read(path) do
      {:ok, binary} ->
        case :erlang.binary_to_term(binary) do
          meta when is_map(meta) -> meta
          _ -> %{}
        end

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  defp write_meta!(storage_dir, shard_id, meta) do
    path = metadata_path(storage_dir, shard_id)
    tmp_path = path <> ".tmp"
    :ok = File.write(tmp_path, :erlang.term_to_binary(meta))
    :ok = File.rename(tmp_path, path)
  end

  defp schedule_flush(%State{flush_interval_ms: interval_ms} = state) do
    ref = Process.send_after(self(), :flush_tick, interval_ms)
    %{state | flush_ref: ref}
  end

  defp metadata_path(storage_dir, shard_id) do
    Path.join(storage_dir, "shard_#{shard_id}.meta")
  end

  defp via_shard(shard_id) do
    {:via, Horde.Registry, {CachePuppyCore.CacheShardRegistry, shard_id}}
  end
end
