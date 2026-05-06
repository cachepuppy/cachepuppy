defmodule CachePuppyCore.Persistence.CacheShardFlushProcess do
  @moduledoc false

  # WAL batching with pause for maintenance. While paused, ops accumulate in pause_q
  # (unbounded — see experimental plan).

  use GenServer
  require Logger

  alias CachePuppyCore.Persistence.CacheConfig
  alias CachePuppyCore.Persistence.CacheUtils

  @default_batch_max 100
  @default_batch_max_ms 20

  defmodule State do
    @moduledoc false
    defstruct [
      :shard_id,
      :current_seq,
      :current_wal_fd,
      :current_wal_bytes,
      :batch_buf,
      :batch_count,
      :batch_timer_ref,
      :paused?,
      :pause_q
    ]
  end

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec enqueue(pid(), term()) :: :ok
  def enqueue(flush_pid, op) when is_pid(flush_pid) do
    GenServer.cast(flush_pid, {:enqueue, op})
  end

  @spec prepare_snapshot(pid()) :: {:ok, pos_integer()} | {:error, term()}
  def prepare_snapshot(flush_pid) when is_pid(flush_pid) do
    GenServer.call(flush_pid, :prepare_snapshot)
  end

  @spec resume_after_snapshot(pid(), pos_integer()) :: :ok | {:error, term()}
  def resume_after_snapshot(flush_pid, open_at_seq)
      when is_pid(flush_pid) and is_integer(open_at_seq) do
    GenServer.call(flush_pid, {:resume_after_snapshot, open_at_seq})
  end

  @spec close_for_rehydration(pid()) :: :ok | {:error, term()}
  def close_for_rehydration(flush_pid) when is_pid(flush_pid) do
    GenServer.call(flush_pid, :close_for_rehydration)
  end

  @spec open_after_rehydration(pid()) :: :ok | {:error, term()}
  def open_after_rehydration(flush_pid) when is_pid(flush_pid) do
    GenServer.call(flush_pid, :open_after_rehydration)
  end

  @impl true
  def init(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)
    _ = File.mkdir_p(CacheConfig.storage_dir())

    case open_latest_wal(shard_id) do
      {:ok, fd, seq, wal_bytes} ->
        {:ok,
         %State{
           shard_id: shard_id,
           current_seq: seq,
           current_wal_fd: fd,
           current_wal_bytes: wal_bytes,
           batch_buf: [],
           batch_count: 0,
           batch_timer_ref: nil,
           paused?: false,
           pause_q: :queue.new()
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:enqueue, op}, state) do
    if state.paused? do
      {:noreply, %{state | pause_q: :queue.in(op, state.pause_q)}}
    else
      case absorb_op(state, op) do
        {:ok, new_state} -> {:noreply, new_state}
        {:error, reason, failed_state} -> {:stop, reason, failed_state}
      end
    end
  end

  @impl true
  def handle_info(:batch_flush, state) do
    state = %{state | batch_timer_ref: nil}

    if state.batch_count > 0 and not state.paused? do
      case flush_batch(state) do
        {:ok, new_state} -> {:noreply, new_state}
        {:error, reason} -> {:stop, reason, state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:prepare_snapshot, _from, state) do
    state = %{state | paused?: true} |> cancel_batch_timer()

    with {:ok, state} <- flush_batch_if_any(state),
         :ok <- sync_fd(state),
         {:ok, included_seq, state} <- seal_wal_for_snapshot_cut(state) do
      {:reply, {:ok, included_seq}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:resume_after_snapshot, open_at_seq}, _from, state) do
    storage_dir = CacheConfig.storage_dir()

    with {:ok, fd} <- open_wal_at_seq(storage_dir, state.shard_id, open_at_seq),
         state <- %{
           state
           | current_wal_fd: fd,
             current_seq: open_at_seq,
             current_wal_bytes: wal_file_size(storage_dir, state.shard_id, open_at_seq),
             paused?: false
         },
         {:ok, state} <- drain_pause_queue(state) do
      {:reply, :ok, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:close_for_rehydration, _from, state) do
    state = %{state | paused?: true} |> cancel_batch_timer()

    with {:ok, state} <- flush_batch_if_any(state),
         :ok <- sync_fd(state),
         {:ok, _, st} <- close_current_segment(state) do
      {:reply, :ok, %{st | current_wal_bytes: 0}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:open_after_rehydration, _from, state) do
    case open_latest_wal(state.shard_id) do
      {:ok, fd, seq, wal_bytes} ->
        state = %{
          state
          | current_wal_fd: fd,
            current_seq: seq,
            current_wal_bytes: wal_bytes,
            paused?: false
        }

        case drain_pause_queue(state) do
          {:ok, state} -> {:reply, :ok, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Drop an empty tail segment (e.g. after rotate) so snapshot includes only segments with data.
  defp seal_wal_for_snapshot_cut(%State{current_wal_fd: nil} = state) do
    {:ok, 0, state}
  end

  defp seal_wal_for_snapshot_cut(state) do
    cond do
      state.current_wal_bytes == 0 and state.current_seq > 1 ->
        with {:ok, _closed_seq, st} <- close_current_segment(state) do
          included_seq = st.current_seq - 1
          {:ok, included_seq, %{st | current_wal_bytes: 0}}
        end

      true ->
        with {:ok, sealed_seq, st} <- close_current_segment(state) do
          {:ok, sealed_seq, %{st | current_wal_bytes: 0}}
        end
    end
  end

  defp absorb_op(state, op) do
    state = maybe_start_batch_timer(state)
    batch_buf = [encode_op(op) | state.batch_buf]
    batch_count = state.batch_count + 1
    state = %{state | batch_buf: batch_buf, batch_count: batch_count}

    if batch_count >= batch_max() do
      case flush_batch(state) do
        {:ok, s} -> {:ok, s}
        {:error, reason} -> {:error, reason, state}
      end
    else
      {:ok, state}
    end
  end

  defp drain_pause_queue(state) do
    case :queue.out(state.pause_q) do
      {:empty, _} ->
        if state.batch_count > 0 do
          case flush_batch(%{state | pause_q: :queue.new()}) do
            {:ok, s} -> {:ok, s}
            {:error, reason} -> {:error, reason}
          end
        else
          {:ok, %{state | pause_q: :queue.new()}}
        end

      {{:value, op}, rest} ->
        state = %{state | pause_q: rest}

        case absorb_op(state, op) do
          {:ok, s} -> drain_pause_queue(s)
          {:error, reason, _} -> {:error, reason}
        end
    end
  end

  defp flush_batch_if_any(%State{batch_count: 0} = state), do: {:ok, state}

  defp flush_batch_if_any(state) do
    case flush_batch(state) do
      {:ok, s} -> {:ok, s}
      {:error, reason} -> {:error, reason}
    end
  end

  defp flush_batch(%State{current_wal_fd: nil} = state) do
    if state.batch_count == 0, do: {:ok, state}, else: {:error, :no_wal_fd}
  end

  defp flush_batch(state) do
    state = cancel_batch_timer(state)
    iodata = Enum.reverse(state.batch_buf)

    case :file.write(state.current_wal_fd, iodata) do
      :ok ->
        bytes = IO.iodata_length(iodata)
        state = %{state | batch_buf: [], batch_count: 0, batch_timer_ref: nil}

        state = %{state | current_wal_bytes: state.current_wal_bytes + bytes}
        state = maybe_rotate(state)

        case :file.sync(state.current_wal_fd) do
          :ok -> {:ok, state}
          {:error, reason} -> {:error, {:sync_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:write_failed, reason}}
    end
  end

  defp maybe_rotate(state) do
    if state.current_wal_fd != nil and
         state.current_wal_bytes >= CacheConfig.wal_segment_max_bytes() do
      case rotate_segment(state) do
        {:ok, new_state} ->
          new_state

        {:error, reason} ->
          Logger.warning(
            "new_cache_flush wal_rotate_failed shard_id=#{state.shard_id} node=#{node()} reason=#{inspect(reason)}"
          )

          state
      end
    else
      state
    end
  end

  defp rotate_segment(state) do
    with :ok <- :file.sync(state.current_wal_fd),
         :ok <- :file.close(state.current_wal_fd) do
      next_seq = state.current_seq + 1
      storage_dir = CacheConfig.storage_dir()
      path = CacheUtils.wal_path(storage_dir, state.shard_id, next_seq)

      case :file.open(String.to_charlist(path), [:append, :binary, :raw]) do
        {:ok, fd} ->
          {:ok,
           %{
             state
             | current_seq: next_seq,
               current_wal_fd: fd,
               current_wal_bytes: 0
           }}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp close_current_segment(%State{current_wal_fd: nil} = state) do
    {:ok, 0, state}
  end

  defp close_current_segment(state) do
    sealed = state.current_seq

    case :file.close(state.current_wal_fd) do
      :ok -> {:ok, sealed, %{state | current_wal_fd: nil}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sync_fd(%State{current_wal_fd: nil}), do: :ok

  defp sync_fd(state) do
    case :file.sync(state.current_wal_fd) do
      :ok -> :ok
      {:error, reason} -> {:error, {:sync_failed, reason}}
    end
  end

  defp open_wal_at_seq(storage_dir, shard_id, seq) do
    path = CacheUtils.wal_path(storage_dir, shard_id, seq)
    :file.open(String.to_charlist(path), [:append, :binary, :raw])
  end

  defp wal_file_size(storage_dir, shard_id, seq) do
    path = CacheUtils.wal_path(storage_dir, shard_id, seq)

    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end

  defp open_latest_wal(shard_id) do
    storage_dir = CacheConfig.storage_dir()
    {seq, size} = latest_wal_segment(storage_dir, shard_id)
    path = CacheUtils.wal_path(storage_dir, shard_id, seq)

    case :file.open(String.to_charlist(path), [:append, :binary, :raw]) do
      {:ok, fd} -> {:ok, fd, seq, size}
      {:error, reason} -> {:error, reason}
    end
  end

  defp latest_wal_segment(storage_dir, shard_id) do
    case CacheUtils.wal_segments(storage_dir, shard_id) do
      [] -> {1, 0}
      segments -> segments |> List.last() |> then(fn {seq, _path, size} -> {seq, size} end)
    end
  end

  defp encode_op({:set, table, key, value, ts_ms, ttl_ms})
       when is_binary(table) and is_binary(key) and is_integer(ts_ms) do
    encode_record({:set, table, key, value, ts_ms, ttl_ms})
  end

  defp encode_op({:delete, table, key, ts_ms})
       when is_binary(table) and is_binary(key) and is_integer(ts_ms) do
    encode_record({:delete, table, key, ts_ms})
  end

  defp encode_record(term) do
    payload = :erlang.term_to_binary(term)
    <<byte_size(payload)::unsigned-integer-size(32), payload::binary>>
  end

  defp maybe_start_batch_timer(%State{batch_timer_ref: nil} = state) do
    ref = Process.send_after(self(), :batch_flush, batch_max_ms())
    %{state | batch_timer_ref: ref}
  end

  defp maybe_start_batch_timer(state), do: state

  defp cancel_batch_timer(%State{batch_timer_ref: nil} = state), do: state

  defp cancel_batch_timer(%State{batch_timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | batch_timer_ref: nil}
  end

  defp batch_max, do: @default_batch_max
  defp batch_max_ms, do: @default_batch_max_ms

  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :shard_id)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent
    }
  end
end
