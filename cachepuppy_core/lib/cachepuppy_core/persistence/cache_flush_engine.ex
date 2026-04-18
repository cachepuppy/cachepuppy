defmodule CachePuppyCore.Persistence.CacheFlushEngine do
  @moduledoc false

  use GenServer
  require Logger

  alias CachePuppyCore.CacheConfig
  alias CachePuppyCore.Persistence.CacheOwnerMeta
  alias CachePuppyCore.Persistence.CacheRecoveryEngine
  alias CachePuppyCore.Persistence.CacheUtils
  alias CachePuppyCore.Persistence.CacheWalReplay

  defmodule ProcessState do
    @moduledoc false
    defstruct shard_id: 0,
              table: nil,
              owner_epoch: 0,
              snapshot_interval_ms: 60_000,
              snapshot_min_wal_bytes: 262_144,
              flush_ref: nil,
              snapshot_task_ref: nil,
              current_seq: 1,
              current_wal_fd: nil,
              current_wal_bytes: 0,
              pending_sync_bytes: 0,
              wal_bytes_since_snapshot: 0,
              last_sync_at_ms: 0,
              last_snapshot_at_ms: 0
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec persist_set(pid(), String.t(), String.t(), term()) :: :ok | {:error, term()}
  def persist_set(pid, table, key, value) do
    GenServer.call(pid, {:persist_set, table, key, value})
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
      current_seq: engine.current_seq,
      current_wal_fd: engine.current_wal_fd,
      current_wal_bytes: engine.current_wal_bytes,
      pending_sync_bytes: engine.pending_sync_bytes,
      wal_bytes_since_snapshot: engine.wal_bytes_since_snapshot,
      last_sync_at_ms: engine.last_sync_at_ms,
      last_snapshot_at_ms: engine.last_snapshot_at_ms
    }

    {:ok, schedule_flush(state)}
  end

  @impl true
  def handle_call({:persist_set, table, key, value}, _from, state) do
    if owner_valid?(state) do
      case append_set(state, table, key, value) |> maybe_rotate_result() do
        {:ok, new_state} ->
          {:reply, :ok, new_state}

        {:error, reason} ->
          Logger.warning(
            "cache_flush persist_set_failed shard_id=#{state.shard_id} node=#{node()} reason=#{inspect(reason)}"
          )

          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :stale_owner}, state}
    end
  end

  @impl true
  def handle_info(:flush_tick, state) do
    state = %{state | flush_ref: nil}
    state = maybe_maintenance(state)
    state = maybe_start_snapshot(state)
    {:noreply, schedule_flush(state)}
  end

  def handle_info({ref, result}, %ProcessState{snapshot_task_ref: ref} = state)
      when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, handle_snapshot_done(state, result)}
  end

  def handle_info(
        {:DOWN, ref, :process, pid, reason},
        %ProcessState{snapshot_task_ref: ref} = state
      )
      when is_pid(pid) do
    Logger.warning(
      "cache_snapshot task_down shard_id=#{state.shard_id} node=#{node()} reason=#{inspect(reason)}"
    )

    {:noreply, %{state | snapshot_task_ref: nil}}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    _ = close_engine(state)
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
     %ProcessState{
       shard_id: shard_id,
       current_seq: current_seq,
       current_wal_fd: wal_fd,
       current_wal_bytes: current_wal_bytes,
       last_sync_at_ms: now_ms,
       last_snapshot_at_ms: now_ms
     }}
  end

  defp close_engine(%ProcessState{current_wal_fd: nil} = state), do: state

  defp close_engine(%ProcessState{current_wal_fd: fd} = state) do
    _ = :file.sync(fd)
    _ = :file.close(fd)
    %{state | current_wal_fd: nil}
  end

  defp append_set(state, table, key, value) do
    record = encode_record({:set, table, key, value, System.system_time(:millisecond)})

    with :ok <- :file.write(state.current_wal_fd, record) do
      bytes = byte_size(record)

      {:ok,
       %{
         state
         | current_wal_bytes: state.current_wal_bytes + bytes,
           wal_bytes_since_snapshot: state.wal_bytes_since_snapshot + bytes,
           pending_sync_bytes: state.pending_sync_bytes + bytes
       }}
    end
  end

  defp maybe_sync(%ProcessState{pending_sync_bytes: 0} = state), do: {:ok, state}

  defp maybe_sync(state) do
    case :file.sync(state.current_wal_fd) do
      :ok ->
        {:ok, %{state | pending_sync_bytes: 0, last_sync_at_ms: System.system_time(:millisecond)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_rotate(state) do
    if state.current_wal_bytes >= CacheConfig.wal_segment_max_bytes() do
      with :ok <- :file.sync(state.current_wal_fd),
           :ok <- :file.close(state.current_wal_fd) do
        next_seq = state.current_seq + 1
        next_path = CacheUtils.wal_path(CacheConfig.storage_dir(), state.shard_id, next_seq)
        {:ok, next_fd} = :file.open(String.to_charlist(next_path), [:append, :binary, :raw])

        {:ok,
         %{
           state
           | current_seq: next_seq,
             current_wal_fd: next_fd,
             current_wal_bytes: 0,
             pending_sync_bytes: 0,
             last_sync_at_ms: System.system_time(:millisecond)
         }}
      end
    else
      {:ok, state}
    end
  end

  defp should_snapshot?(state) do
    now_ms = System.system_time(:millisecond)
    wal_ready = state.wal_bytes_since_snapshot >= state.snapshot_min_wal_bytes
    interval_ready = now_ms - state.last_snapshot_at_ms >= state.snapshot_interval_ms
    wal_ready and interval_ready
  end

  defp finalize_snapshot(state, cutoff_seq) do
    checkpoint = %{
      "snapshot_cutoff_seq" => cutoff_seq,
      "updated_at_ms" => System.system_time(:millisecond)
    }

    storage_dir = CacheConfig.storage_dir()
    :ok = write_term_file(CacheUtils.checkpoint_path(storage_dir, state.shard_id), checkpoint)
    _ = prune_wal_segments(storage_dir, state.shard_id, cutoff_seq)
    {:ok, %{state | wal_bytes_since_snapshot: 0}}
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
    with_valid_owner(state, fn s -> maybe_sync(s) |> maybe_rotate_result() end)
  end

  defp maybe_start_snapshot(%ProcessState{snapshot_task_ref: ref} = state) when not is_nil(ref),
    do: state

  defp maybe_start_snapshot(state) do
    if snapshot_allowed?() and owner_valid?(state) and should_snapshot?(state) do
      storage_dir = CacheConfig.storage_dir()
      checkpoint_seq = CacheRecoveryEngine.read_checkpoint_seq(storage_dir, state.shard_id)

      case prepare_snapshot_wal_boundary(state) do
        {:ok, state_after} ->
          included_seq = state_after.current_seq - 1
          finalize_cutoff = state_after.current_seq
          started_state = %{state_after | last_snapshot_at_ms: System.system_time(:millisecond)}
          shard_id = state.shard_id

          task =
            Task.Supervisor.async_nolink(CachePuppyCore.FlushTaskSupervisor, fn ->
              result =
                CacheWalReplay.materialize_snapshot_from_wal(
                  storage_dir,
                  shard_id,
                  checkpoint_seq,
                  included_seq
                )

              {:snapshot_done, result, finalize_cutoff}
            end)

          %{started_state | snapshot_task_ref: task.ref}

        {:error, reason} ->
          Logger.warning(
            "cache_snapshot prepare_failed shard_id=#{state.shard_id} node=#{node()} reason=#{inspect(reason)}"
          )

          state
      end
    else
      state
    end
  end

  defp prepare_snapshot_wal_boundary(state) do
    with {:ok, s1} <- maybe_sync(state),
         {:ok, s2} <- force_rotate_for_snapshot(s1) do
      {:ok, s2}
    end
  end

  defp force_rotate_for_snapshot(%ProcessState{current_wal_fd: nil}), do: {:error, :no_wal_fd}

  defp force_rotate_for_snapshot(state) do
    next_seq = state.current_seq + 1
    next_path = CacheUtils.wal_path(CacheConfig.storage_dir(), state.shard_id, next_seq)

    case :file.open(String.to_charlist(next_path), [:append, :binary, :raw]) do
      {:ok, new_fd} ->
        case :file.sync(state.current_wal_fd) do
          :ok ->
            case :file.close(state.current_wal_fd) do
              :ok ->
                now_ms = System.system_time(:millisecond)

                {:ok,
                 %{
                   state
                   | current_seq: next_seq,
                     current_wal_fd: new_fd,
                     current_wal_bytes: 0,
                     pending_sync_bytes: 0,
                     last_sync_at_ms: now_ms
                 }}

              {:error, reason} ->
                _ = :file.close(new_fd)
                {:error, {:close_old_wal, reason}}
            end

          {:error, reason} ->
            _ = :file.close(new_fd)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_snapshot_done(state, {:snapshot_done, :ok, finalize_cutoff}) do
    if snapshot_allowed?() do
      with_valid_owner(clear_snapshot_task(state), fn s ->
        {:ok, next_state} = finalize_snapshot(s, finalize_cutoff)

        Logger.info(
          "cache_snapshot success shard_id=#{state.shard_id} node=#{node()} cutoff_seq=#{finalize_cutoff}"
        )

        {:ok, next_state}
      end)
    else
      Logger.warning(
        "cache_snapshot skipped_finalize shard_id=#{state.shard_id} node=#{node()} reason=quorum_snapshot_blocked"
      )

      clear_snapshot_task(state)
    end
  end

  defp handle_snapshot_done(state, {:snapshot_done, {:error, reason}, _finalize_cutoff}) do
    Logger.warning(
      "cache_snapshot failed shard_id=#{state.shard_id} node=#{node()} reason=#{inspect(reason)}"
    )

    clear_snapshot_task(state)
  end

  defp snapshot_allowed? do
    not CachePuppyCore.ClusterQuorumGuard.snapshot_blocked?()
  end

  defp schedule_flush(%ProcessState{} = state) do
    ref = Process.send_after(self(), :flush_tick, CacheConfig.flush_interval_ms())
    %{state | flush_ref: ref}
  end

  defp owner_valid?(%ProcessState{shard_id: shard_id, owner_epoch: epoch}) do
    CacheOwnerMeta.owner_valid?(CacheConfig.storage_dir(), shard_id, epoch, to_string(node()))
  end

  defp clear_snapshot_task(state) do
    %{state | snapshot_task_ref: nil}
  end

  defp with_valid_owner(state, fun) do
    if owner_valid?(state) do
      case fun.(state) do
        {:ok, next_state} ->
          next_state

        {:error, reason} ->
          Logger.warning(
            "cache_flush operation_failed shard_id=#{state.shard_id} node=#{node()} reason=#{inspect(reason)}"
          )

          state
      end
    else
      state
    end
  end

  defp maybe_rotate_result({:ok, state}), do: maybe_rotate(state)
  defp maybe_rotate_result(error), do: error
end
