defmodule CachePuppyCore.Persistence.CacheFlushEngine do
  @moduledoc false

  alias CachePuppyCore.CacheConfig
  alias CachePuppyCore.Persistence.CacheUtils

  defstruct shard_id: nil,
            current_seq: 1,
            current_wal_fd: nil,
            current_wal_bytes: 0,
            pending_sync_bytes: 0,
            wal_bytes_since_snapshot: 0,
            last_sync_at_ms: 0,
            last_snapshot_at_ms: 0

  @type t :: %__MODULE__{
          shard_id: non_neg_integer(),
          current_seq: pos_integer(),
          current_wal_fd: :file.io_device() | nil,
          current_wal_bytes: non_neg_integer(),
          pending_sync_bytes: non_neg_integer(),
          wal_bytes_since_snapshot: non_neg_integer(),
          last_sync_at_ms: integer(),
          last_snapshot_at_ms: integer()
        }

  @spec init(keyword()) :: {:ok, t()}
  def init(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)
    storage_dir = CacheConfig.storage_dir()
    _ = File.mkdir_p(storage_dir)

    {current_seq, current_wal_bytes} = latest_wal_segment(storage_dir, shard_id)
    wal_path = CacheUtils.wal_path(storage_dir, shard_id, current_seq)
    {:ok, wal_fd} = :file.open(String.to_charlist(wal_path), [:append, :binary, :raw])
    now_ms = System.system_time(:millisecond)

    {:ok,
     %__MODULE__{
       shard_id: shard_id,
       current_seq: current_seq,
       current_wal_fd: wal_fd,
       current_wal_bytes: current_wal_bytes,
       last_sync_at_ms: now_ms,
       last_snapshot_at_ms: now_ms
     }}
  end

  @spec close(t()) :: t()
  def close(%__MODULE__{current_wal_fd: nil} = engine), do: engine

  def close(%__MODULE__{current_wal_fd: fd} = engine) do
    _ = :file.sync(fd)
    _ = :file.close(fd)
    %{engine | current_wal_fd: nil}
  end

  @spec append_set(t(), String.t(), String.t(), term()) :: {:ok, t()} | {:error, term()}
  def append_set(%__MODULE__{} = engine, table, key, value) do
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

  @spec maybe_sync(t()) :: {:ok, t()} | {:error, term()}
  def maybe_sync(%__MODULE__{pending_sync_bytes: 0} = engine), do: {:ok, engine}

  def maybe_sync(%__MODULE__{} = engine) do
    case :file.sync(engine.current_wal_fd) do
      :ok ->
        {:ok,
         %{engine | pending_sync_bytes: 0, last_sync_at_ms: System.system_time(:millisecond)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec maybe_rotate(t()) :: {:ok, t()} | {:error, term()}
  def maybe_rotate(%__MODULE__{} = engine) do
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

  @spec should_snapshot?(t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def should_snapshot?(%__MODULE__{} = engine, snapshot_interval_ms, snapshot_min_wal_bytes) do
    now_ms = System.system_time(:millisecond)

    wal_ready = engine.wal_bytes_since_snapshot >= snapshot_min_wal_bytes
    interval_ready = now_ms - engine.last_snapshot_at_ms >= snapshot_interval_ms
    wal_ready and interval_ready
  end

  @spec mark_snapshot_started(t()) :: t()
  def mark_snapshot_started(%__MODULE__{} = engine) do
    %{engine | last_snapshot_at_ms: System.system_time(:millisecond)}
  end

  @spec snapshot_cutoff_seq(t()) :: pos_integer()
  def snapshot_cutoff_seq(%__MODULE__{} = engine), do: engine.current_seq

  @spec finalize_snapshot(t(), pos_integer()) :: {:ok, t()}
  def finalize_snapshot(%__MODULE__{} = engine, cutoff_seq) do
    checkpoint = %{
      "snapshot_cutoff_seq" => cutoff_seq,
      "updated_at_ms" => System.system_time(:millisecond)
    }

    storage_dir = CacheConfig.storage_dir()
    :ok = write_term_file(CacheUtils.checkpoint_path(storage_dir, engine.shard_id), checkpoint)
    _ = prune_wal_segments(storage_dir, engine.shard_id, cutoff_seq)
    {:ok, %{engine | wal_bytes_since_snapshot: 0}}
  end

  @spec write_snapshot(:ets.tid(), non_neg_integer()) :: :ok | {:error, term()}
  def write_snapshot(table, shard_id) do
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
end
