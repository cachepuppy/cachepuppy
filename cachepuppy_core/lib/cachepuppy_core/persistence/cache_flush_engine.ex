defmodule CachePuppyCore.Persistence.CacheFlushEngine do
  @moduledoc false

  use GenServer
  require Logger

  alias CachePuppyCore.CacheConfig
  alias CachePuppyCore.Persistence.CacheUtils

  defmodule EngineState do
    @moduledoc false
    defstruct shard_id: nil,
              current_seq: 1,
              current_wal_fd: nil,
              current_wal_bytes: 0,
              pending_sync_bytes: 0,
              wal_bytes_since_snapshot: 0,
              last_sync_at_ms: 0,
              last_snapshot_at_ms: 0
  end

  defmodule ProcessState do
    @moduledoc false
    defstruct shard_id: 0,
              table: nil,
              owner_epoch: 0,
              snapshot_interval_ms: 60_000,
              snapshot_min_wal_bytes: 262_144,
              flush_ref: nil,
              snapshot_task_ref: nil,
              engine: nil
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec persist_set(pid(), String.t(), String.t(), term()) :: :ok
  def persist_set(pid, table, key, value) do
    GenServer.cast(pid, {:persist_set, table, key, value})
  end

  @impl true
  def init(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)
    table = Keyword.fetch!(opts, :table)
    owner_epoch = Keyword.fetch!(opts, :owner_epoch)
    snapshot_interval_ms = Keyword.fetch!(opts, :snapshot_interval_ms)
    snapshot_min_wal_bytes = Keyword.fetch!(opts, :snapshot_min_wal_bytes)
    {:ok, engine} = open_engine(shard_id)

    state = %ProcessState{
      shard_id: shard_id,
      table: table,
      owner_epoch: owner_epoch,
      snapshot_interval_ms: snapshot_interval_ms,
      snapshot_min_wal_bytes: snapshot_min_wal_bytes,
      engine: engine
    }

    {:ok, schedule_flush(state)}
  end

  @impl true
  def handle_cast({:persist_set, table, key, value}, state) do
    state =
      if owner_valid?(state) do
        with {:ok, engine} <- append_set(state.engine, table, key, value),
             {:ok, engine} <- maybe_rotate(engine) do
          %{state | engine: engine}
        else
          {:error, reason} ->
            Logger.warning(
              "cache_set wal_failed shard_id=#{state.shard_id} node=#{node()} reason=#{inspect(reason)}"
            )

            state
        end
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:flush_tick, state) do
    state = %{state | flush_ref: nil}
    state = maybe_maintenance(state)
    state = maybe_start_snapshot(state)
    {:noreply, schedule_flush(state)}
  end

  def handle_info(
        {:snapshot_done, ref, result, cutoff_seq},
        %ProcessState{snapshot_task_ref: ref} = state
      ) do
    {:noreply, handle_snapshot_done(state, result, cutoff_seq)}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %ProcessState{engine: engine}) do
    _ = close_engine(engine)
    :ok
  end

  defp open_engine(shard_id) do
    storage_dir = CacheConfig.storage_dir()
    _ = File.mkdir_p(storage_dir)

    {current_seq, current_wal_bytes} = latest_wal_segment(storage_dir, shard_id)
    wal_path = CacheUtils.wal_path(storage_dir, shard_id, current_seq)
    {:ok, wal_fd} = :file.open(String.to_charlist(wal_path), [:append, :binary, :raw])
    now_ms = System.system_time(:millisecond)

    {:ok,
     %EngineState{
       shard_id: shard_id,
       current_seq: current_seq,
       current_wal_fd: wal_fd,
       current_wal_bytes: current_wal_bytes,
       last_sync_at_ms: now_ms,
       last_snapshot_at_ms: now_ms
     }}
  end

  defp close_engine(%EngineState{current_wal_fd: nil} = engine), do: engine

  defp close_engine(%EngineState{current_wal_fd: fd} = engine) do
    _ = :file.sync(fd)
    _ = :file.close(fd)
    %{engine | current_wal_fd: nil}
  end

  defp append_set(%EngineState{} = engine, table, key, value) do
    record = encode_record({:set, table, key, value, System.system_time(:millisecond)})

    with :ok <- :file.write(engine.current_wal_fd, record) do
      bytes = byte_size(record)

      {:ok,
       %{
         engine
         | current_wal_bytes: engine.current_wal_bytes + bytes,
           wal_bytes_since_snapshot: engine.wal_bytes_since_snapshot + bytes,
           pending_sync_bytes: engine.pending_sync_bytes + bytes
       }}
    end
  end

  defp maybe_sync(%EngineState{pending_sync_bytes: 0} = engine), do: {:ok, engine}

  defp maybe_sync(%EngineState{} = engine) do
    case :file.sync(engine.current_wal_fd) do
      :ok ->
        {:ok,
         %{engine | pending_sync_bytes: 0, last_sync_at_ms: System.system_time(:millisecond)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_rotate(%EngineState{} = engine) do
    if engine.current_wal_bytes >= CacheConfig.wal_segment_max_bytes() do
      with :ok <- :file.sync(engine.current_wal_fd),
           :ok <- :file.close(engine.current_wal_fd) do
        next_seq = engine.current_seq + 1
        next_path = CacheUtils.wal_path(CacheConfig.storage_dir(), engine.shard_id, next_seq)
        {:ok, next_fd} = :file.open(String.to_charlist(next_path), [:append, :binary, :raw])

        {:ok,
         %{
           engine
           | current_seq: next_seq,
             current_wal_fd: next_fd,
             current_wal_bytes: 0,
             pending_sync_bytes: 0,
             last_sync_at_ms: System.system_time(:millisecond)
         }}
      end
    else
      {:ok, engine}
    end
  end

  defp should_snapshot?(%EngineState{} = engine, snapshot_interval_ms, snapshot_min_wal_bytes) do
    now_ms = System.system_time(:millisecond)

    wal_ready = engine.wal_bytes_since_snapshot >= snapshot_min_wal_bytes
    interval_ready = now_ms - engine.last_snapshot_at_ms >= snapshot_interval_ms
    wal_ready and interval_ready
  end

  defp mark_snapshot_started(%EngineState{} = engine) do
    %{engine | last_snapshot_at_ms: System.system_time(:millisecond)}
  end

  defp snapshot_cutoff_seq(%EngineState{} = engine), do: engine.current_seq

  defp finalize_snapshot(%EngineState{} = engine, cutoff_seq) do
    checkpoint = %{
      "snapshot_cutoff_seq" => cutoff_seq,
      "updated_at_ms" => System.system_time(:millisecond)
    }

    storage_dir = CacheConfig.storage_dir()
    :ok = write_term_file(CacheUtils.checkpoint_path(storage_dir, engine.shard_id), checkpoint)
    _ = prune_wal_segments(storage_dir, engine.shard_id, cutoff_seq)
    {:ok, %{engine | wal_bytes_since_snapshot: 0}}
  end

  defp write_snapshot(table, shard_id) do
    storage_dir = CacheConfig.storage_dir()
    tmp_path = CacheUtils.snapshot_temp_path(storage_dir, shard_id)
    final_path = CacheUtils.snapshot_path(storage_dir, shard_id)

    with :ok <- :ets.tab2file(table, String.to_charlist(tmp_path), sync: true),
         :ok <- File.rename(tmp_path, final_path) do
      :ok
    end
  end

  defp encode_record(term) do
    payload = :erlang.term_to_binary(term)
    <<byte_size(payload)::unsigned-integer-size(32), payload::binary>>
  end

  defp latest_wal_segment(storage_dir, shard_id) do
    case CacheUtils.wal_segments(storage_dir, shard_id) do
      [] -> {1, 0}
      segments -> List.last(segments) |> then(fn {seq, _path, size} -> {seq, size} end)
    end
  end

  defp prune_wal_segments(storage_dir, shard_id, cutoff_seq) do
    CacheUtils.wal_segments(storage_dir, shard_id)
    |> Enum.each(fn {seq, path, _size} ->
      if seq < cutoff_seq do
        _ = File.rm(path)
      end
    end)
  end

  defp write_term_file(path, term) do
    tmp_path = path <> ".tmp"
    :ok = File.write(tmp_path, :erlang.term_to_binary(term))
    :ok = File.rename(tmp_path, path)
  end

  defp maybe_maintenance(state) do
    if owner_valid?(state) do
      with {:ok, engine} <- maybe_sync(state.engine),
           {:ok, engine} <- maybe_rotate(engine) do
        %{state | engine: engine}
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

  defp maybe_start_snapshot(%ProcessState{snapshot_task_ref: ref} = state) when not is_nil(ref),
    do: state

  defp maybe_start_snapshot(state) do
    if owner_valid?(state) and
         should_snapshot?(
           state.engine,
           state.snapshot_interval_ms,
           state.snapshot_min_wal_bytes
         ) do
      engine = mark_snapshot_started(state.engine)
      cutoff_seq = snapshot_cutoff_seq(engine)
      caller = self()
      table = state.table
      shard_id = state.shard_id
      ref = make_ref()

      _pid =
        spawn(fn ->
          result = write_snapshot(table, shard_id)
          send(caller, {:snapshot_done, ref, result, cutoff_seq})
        end)

      %{state | engine: engine, snapshot_task_ref: ref}
    else
      state
    end
  end

  defp handle_snapshot_done(state, :ok, cutoff_seq) do
    if owner_valid?(state) do
      {:ok, engine} = finalize_snapshot(state.engine, cutoff_seq)

      Logger.info(
        "cache_snapshot success shard_id=#{state.shard_id} node=#{node()} cutoff_seq=#{cutoff_seq}"
      )

      %{state | engine: engine, snapshot_task_ref: nil}
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

  defp owner_valid?(%ProcessState{shard_id: shard_id, owner_epoch: epoch}) do
    storage_dir = CacheConfig.storage_dir()
    path = Path.join(storage_dir, "shard_#{shard_id}.meta")

    meta =
      case File.read(path) do
        {:ok, binary} ->
          case :erlang.binary_to_term(binary) do
            loaded when is_map(loaded) -> loaded
            _ -> %{}
          end

        _ ->
          %{}
      end

    Map.get(meta, "epoch") == epoch and
      Map.get(meta, "owner_node") == to_string(node()) and
      Map.get(meta, "rehydrating") == false
  rescue
    _ -> false
  end

  defp schedule_flush(%ProcessState{} = state) do
    ref = Process.send_after(self(), :flush_tick, CacheConfig.flush_interval_ms())
    %{state | flush_ref: ref}
  end
end
