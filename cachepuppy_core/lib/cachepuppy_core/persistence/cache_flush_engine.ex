defmodule CachePuppyCore.Persistence.CacheFlushEngine do
  @moduledoc false

  require Logger

  alias CachePuppyCore.Persistence.CacheConfig
  alias CachePuppyCore.Persistence.CacheRecoveryEngine
  alias CachePuppyCore.Persistence.CacheUtils
  alias CachePuppyCore.Persistence.CacheWalReplay

  defmodule FlushState do
    @moduledoc false
    defstruct shard_id: 0,
              owner_epoch: 0,
              snapshot_task_ref: nil,
              current_seq: 1,
              current_wal_fd: nil,
              current_wal_bytes: 0,
              pending_sync_bytes: 0,
              wal_bytes_since_snapshot: 0,
              last_sync_at_ms: 0,
              last_snapshot_at_ms: 0
  end

  @spec open(non_neg_integer(), non_neg_integer()) :: {:ok, %FlushState{}}
  def open(shard_id, owner_epoch) when is_integer(shard_id) and is_integer(owner_epoch) do
    {:ok, wal} = open_wal(shard_id)

    {:ok,
     %FlushState{
       shard_id: shard_id,
       owner_epoch: owner_epoch,
       current_seq: wal.current_seq,
       current_wal_fd: wal.current_wal_fd,
       current_wal_bytes: wal.current_wal_bytes,
       last_sync_at_ms: wal.now_ms,
       last_snapshot_at_ms: wal.now_ms
     }}
  end

  @spec close(%FlushState{}) :: %FlushState{}
  def close(%FlushState{} = state), do: close_wal(state)

  @spec sync_and_close_wal(%FlushState{}) :: {:ok, %FlushState{}} | {:error, term()}
  def sync_and_close_wal(%FlushState{current_wal_fd: nil} = flush), do: {:ok, flush}

  def sync_and_close_wal(%FlushState{current_wal_fd: fd} = flush) do
    with :ok <- :file.sync(fd),
         :ok <- :file.close(fd) do
      {:ok,
       %{
         flush
         | current_wal_fd: nil,
           current_wal_bytes: 0,
           pending_sync_bytes: 0
       }}
    end
  end

  @spec persist_set(%FlushState{}, boolean(), String.t(), String.t(), term(), nil | pos_integer()) ::
          {:ok, %FlushState{}, pos_integer()} | {:error, term()}
  def persist_set(%FlushState{} = flush, owner_valid?, table, key, value, ttl_ms \\ nil)
      when is_boolean(owner_valid?) do
    if owner_valid? do
      case append_set(flush, table, key, value, ttl_ms) |> maybe_rotate_result() do
        {:ok, {new_flush, ts_ms}} ->
          {:ok, new_flush, ts_ms}

        {:error, reason} ->
          Logger.warning(
            "cache_flush persist_set_failed shard_id=#{flush.shard_id} node=#{node()} reason=#{inspect(reason)}"
          )

          {:error, reason}
      end
    else
      {:error, :stale_owner}
    end
  end

  @spec persist_delete(%FlushState{}, boolean(), String.t(), String.t()) ::
          {:ok, %FlushState{}} | {:error, term()}
  def persist_delete(%FlushState{} = flush, owner_valid?, table, key)
      when is_boolean(owner_valid?) do
    if owner_valid? do
      case append_delete(flush, table, key) |> maybe_rotate_result() do
        {:ok, new_flush} ->
          {:ok, new_flush}

        {:error, reason} ->
          Logger.warning(
            "cache_flush persist_delete_failed shard_id=#{flush.shard_id} node=#{node()} reason=#{inspect(reason)}"
          )

          {:error, reason}
      end
    else
      {:error, :stale_owner}
    end
  end

  @spec on_flush_tick(%FlushState{}, boolean(), boolean(), atom()) :: %FlushState{}
  def on_flush_tick(
        %FlushState{} = flush,
        wal_sync_allowed?,
        owner_valid?,
        rehydration_phase
      )
      when is_boolean(wal_sync_allowed?) and is_boolean(owner_valid?) and
             is_atom(rehydration_phase) do
    flush =
      if wal_sync_allowed? do
        case maybe_sync(flush) |> maybe_rotate_result() do
          {:ok, f} -> f
          {:error, _} -> flush
        end
      else
        flush
      end

    maybe_start_snapshot(flush, owner_valid?, rehydration_phase)
  end

  @spec on_snapshot_message(%FlushState{}, term(), boolean(), atom()) :: %FlushState{}
  def on_snapshot_message(%FlushState{} = flush, message, owner_valid?, rehydration_phase)
      when is_boolean(owner_valid?) and is_atom(rehydration_phase) do
    case message do
      {:snapshot_done, :ok, finalize_cutoff} ->
        flush_cleared = %{flush | snapshot_task_ref: nil}

        if snapshot_allowed?(rehydration_phase) do
          with_valid_owner(flush_cleared, owner_valid?, fn s ->
            {:ok, next} = finalize_snapshot(s, finalize_cutoff)

            Logger.info(
              "cache_snapshot success shard_id=#{flush.shard_id} node=#{node()} cutoff_seq=#{finalize_cutoff}"
            )

            {:ok, next}
          end)
        else
          Logger.warning(
            "cache_snapshot skipped_finalize shard_id=#{flush.shard_id} node=#{node()} reason=rehydration_phase_blocked"
          )

          flush_cleared
        end

      {:snapshot_done, {:error, reason}, _} ->
        Logger.warning(
          "cache_snapshot failed shard_id=#{flush.shard_id} node=#{node()} reason=#{inspect(reason)}"
        )

        %{flush | snapshot_task_ref: nil}

      _ ->
        flush
    end
  end

  @spec clear_snapshot_task_ref(%FlushState{}) :: %FlushState{}
  def clear_snapshot_task_ref(flush), do: %{flush | snapshot_task_ref: nil}

  defp open_wal(shard_id) do
    storage_dir = CacheConfig.storage_dir()
    _ = File.mkdir_p(storage_dir)

    {current_seq, current_wal_bytes} = latest_wal_segment(storage_dir, shard_id)
    wal_path = CacheUtils.wal_path(storage_dir, shard_id, current_seq)
    {:ok, wal_fd} = :file.open(String.to_charlist(wal_path), [:append, :binary, :raw])
    now_ms = System.system_time(:millisecond)

    {:ok,
     %{
       current_seq: current_seq,
       current_wal_fd: wal_fd,
       current_wal_bytes: current_wal_bytes,
       now_ms: now_ms
     }}
  end

  defp close_wal(%FlushState{current_wal_fd: nil} = state), do: state

  defp close_wal(%FlushState{current_wal_fd: fd} = state) do
    _ = :file.sync(fd)
    _ = :file.close(fd)
    %{state | current_wal_fd: nil}
  end

  defp append_set(state, table, key, value, ttl_ms) do
    ts_ms = System.system_time(:millisecond)
    record = encode_record({:set, table, key, value, ts_ms, ttl_ms})

    with :ok <- :file.write(state.current_wal_fd, record) do
      bytes = byte_size(record)

      {:ok,
       {%{
          state
          | current_wal_bytes: state.current_wal_bytes + bytes,
            wal_bytes_since_snapshot: state.wal_bytes_since_snapshot + bytes,
            pending_sync_bytes: state.pending_sync_bytes + bytes
        }, ts_ms}}
    end
  end

  defp append_delete(state, table, key) do
    ts_ms = System.system_time(:millisecond)
    record = encode_record({:delete, table, key, ts_ms})

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

  defp maybe_sync(%FlushState{pending_sync_bytes: 0} = state), do: {:ok, state}

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
    wal_ready = state.wal_bytes_since_snapshot >= CacheConfig.snapshot_min_wal_bytes()
    interval_ready = now_ms - state.last_snapshot_at_ms >= CacheConfig.snapshot_interval_ms()
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

  defp maybe_start_snapshot(%FlushState{snapshot_task_ref: ref} = flush, _owner_valid?, _phase)
       when not is_nil(ref),
       do: flush

  defp maybe_start_snapshot(%FlushState{} = flush, owner_valid?, rehydration_phase) do
    if snapshot_allowed?(rehydration_phase) and owner_valid? and should_snapshot?(flush) do
      storage_dir = CacheConfig.storage_dir()
      checkpoint_seq = CacheRecoveryEngine.read_checkpoint_seq(storage_dir, flush.shard_id)

      case prepare_snapshot_wal_boundary(flush) do
        {:ok, flush_after} ->
          included_seq = flush_after.current_seq - 1
          finalize_cutoff = flush_after.current_seq
          started = %{flush_after | last_snapshot_at_ms: System.system_time(:millisecond)}
          shard_id = flush.shard_id

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

          %{started | snapshot_task_ref: task.ref}

        {:error, reason} ->
          Logger.warning(
            "cache_snapshot prepare_failed shard_id=#{flush.shard_id} node=#{node()} reason=#{inspect(reason)}"
          )

          flush
      end
    else
      flush
    end
  end

  defp prepare_snapshot_wal_boundary(flush) do
    with {:ok, s1} <- maybe_sync(flush) |> maybe_rotate_result(),
         {:ok, s2} <- force_rotate_for_snapshot(s1) do
      {:ok, s2}
    end
  end

  defp force_rotate_for_snapshot(%FlushState{current_wal_fd: nil}), do: {:error, :no_wal_fd}

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

  defp snapshot_allowed?(rehydration_phase), do: rehydration_phase == :success

  defp with_valid_owner(flush, owner_valid?, fun) do
    if owner_valid? do
      case fun.(flush) do
        {:ok, next_flush} ->
          next_flush

        {:error, reason} ->
          Logger.warning(
            "cache_flush operation_failed shard_id=#{flush.shard_id} node=#{node()} reason=#{inspect(reason)}"
          )

          flush

        other ->
          Logger.warning(
            "cache_flush unexpected_result shard_id=#{flush.shard_id} node=#{node()} result=#{inspect(other)}"
          )

          flush
      end
    else
      flush
    end
  end

  defp maybe_rotate_result({:ok, {%FlushState{} = state, ts_ms}}) do
    case maybe_rotate(state) do
      {:ok, rotated} -> {:ok, {rotated, ts_ms}}
      {:error, _} = err -> err
    end
  end

  defp maybe_rotate_result({:ok, %FlushState{} = state}), do: maybe_rotate(state)
  defp maybe_rotate_result(error), do: error
end
