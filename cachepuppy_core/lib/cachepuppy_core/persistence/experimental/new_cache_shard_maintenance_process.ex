defmodule CachePuppyCore.Persistence.Experimental.NewCacheShardMaintenanceProcess do
  @moduledoc false

  # Serialized snapshot + rehydration. Inline WAL decode/replay/materialize — no
  # CacheRecoveryEngine / CacheWalReplay calls.

  use GenServer
  require Logger

  alias CachePuppyCore.Persistence.CacheConfig
  alias CachePuppyCore.Persistence.Experimental.NewCacheEntry
  alias CachePuppyCore.Persistence.Experimental.NewCacheUtils
  alias CachePuppyCore.Persistence.Experimental.NewCacheShardFlushProcess

  defmodule State do
    @moduledoc false
    defstruct [:shard_id, :flush_pid]
  end

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec load_from_disk(pid()) :: {:ok, :ets.tid()} | {:error, term()}
  def load_from_disk(pid) when is_pid(pid), do: GenServer.call(pid, :load_from_disk)

  @spec snapshot(pid()) :: :ok | {:error, term()}
  def snapshot(pid) when is_pid(pid), do: GenServer.call(pid, :snapshot)

  @impl true
  def init(opts) do
    {:ok,
     %State{
       shard_id: Keyword.fetch!(opts, :shard_id),
       flush_pid: Keyword.fetch!(opts, :flush_pid)
     }}
  end

  @impl true
  def handle_call(:load_from_disk, _from, state) do
    storage_dir = CacheConfig.storage_dir()

    result =
      with :ok <- NewCacheShardFlushProcess.close_for_rehydration(state.flush_pid) do
        {:ok, load_snapshot_then_replay(state.shard_id, storage_dir)}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    storage_dir = CacheConfig.storage_dir()
    checkpoint_seq = read_checkpoint_seq(storage_dir, state.shard_id)

    result =
      with {:ok, included_seq} <- NewCacheShardFlushProcess.prepare_snapshot(state.flush_pid),
           :ok <- materialize_snapshot(storage_dir, state.shard_id, checkpoint_seq, included_seq),
           cutoff = included_seq + 1,
           :ok <- write_checkpoint!(storage_dir, state.shard_id, cutoff) do
        prune_wal_segments(storage_dir, state.shard_id, cutoff)
        NewCacheShardFlushProcess.resume_after_snapshot(state.flush_pid, cutoff)
      end

    {:reply, result, state}
  end

  defp read_checkpoint_seq(storage_dir, shard_id) do
    path = NewCacheUtils.checkpoint_path(storage_dir, shard_id)

    case File.read(path) do
      {:ok, binary} ->
        case :erlang.binary_to_term(binary) do
          %{"snapshot_cutoff_seq" => seq} when is_integer(seq) and seq > 0 -> seq
          _ -> 1
        end

      _ ->
        1
    end
  rescue
    _ -> 1
  end

  defp write_checkpoint!(storage_dir, shard_id, cutoff_seq) do
    path = NewCacheUtils.checkpoint_path(storage_dir, shard_id)
    tmp_path = path <> ".tmp"

    term = %{
      "snapshot_cutoff_seq" => cutoff_seq,
      "updated_at_ms" => System.system_time(:millisecond)
    }

    with :ok <- File.write(tmp_path, :erlang.term_to_binary(term)),
         :ok <- File.rename(tmp_path, path) do
      :ok
    end
  end

  defp prune_wal_segments(storage_dir, shard_id, cutoff_seq) do
    NewCacheUtils.wal_segments(storage_dir, shard_id)
    |> Enum.each(fn {seq, path, _size} ->
      if seq < cutoff_seq, do: _ = File.rm(path)
    end)

    :ok
  end

  defp load_snapshot_then_replay(shard_id, storage_dir) do
    table = open_snapshot_table(storage_dir, shard_id, :protected, log: true)
    checkpoint_seq = read_checkpoint_seq(storage_dir, shard_id)

    storage_dir
    |> NewCacheUtils.wal_segments(shard_id)
    |> Enum.filter(fn {seq, _, _} -> seq >= checkpoint_seq end)
    |> Enum.take(CacheConfig.recovery_max_segments())
    |> Enum.each(fn {_seq, path, _size} ->
      replay_wal_path_into_table(table, path, persist_truncate: true, log_read_errors: true)
    end)

    table
  end

  defp materialize_snapshot(storage_dir, shard_id, checkpoint_seq, included_seq) do
    base = open_snapshot_table(storage_dir, shard_id, :private, log: false)

    try do
      segments =
        storage_dir
        |> NewCacheUtils.wal_segments(shard_id)
        |> Enum.filter(fn {seq, _, _} -> seq >= checkpoint_seq and seq <= included_seq end)
        |> Enum.sort_by(fn {seq, _, _} -> seq end)

      Enum.each(segments, fn {_seq, path, _size} ->
        replay_wal_path_into_table(base, path, persist_truncate: false, log_read_errors: false)
      end)

      tmp_path = NewCacheUtils.snapshot_temp_path(storage_dir, shard_id)
      final_path = NewCacheUtils.snapshot_path(storage_dir, shard_id)
      _ = File.rm(tmp_path)

      with :ok <- :ets.tab2file(base, String.to_charlist(tmp_path), sync: true),
           :ok <- File.rename(tmp_path, final_path) do
        :ok
      else
        {:error, _} = err -> err
        other -> {:error, other}
      end
    after
      :ets.delete(base)
    end
  end

  defp open_snapshot_table(storage_dir, shard_id, access, opts)
       when access in [:private, :protected] do
    log? = Keyword.fetch!(opts, :log)
    path = NewCacheUtils.snapshot_path(storage_dir, shard_id)

    case :ets.file2tab(String.to_charlist(path)) do
      {:ok, tid} ->
        if log? do
          Logger.info(
            "new_cache_rehydrate loaded_snapshot shard_id=#{shard_id} node=#{node()} path=#{path}"
          )
        end

        tid

      {:error, reason} ->
        if log? do
          Logger.info(
            "new_cache_rehydrate cold_start shard_id=#{shard_id} node=#{node()} path=#{path} reason=#{inspect(reason)}"
          )
        end

        :ets.new(__MODULE__, [:set, access])
    end
  end

  defp replay_wal_path_into_table(table, path, opts) do
    persist_truncate? = Keyword.get(opts, :persist_truncate, true)
    log_read_errors? = Keyword.get(opts, :log_read_errors, false)

    case File.read(path) do
      {:ok, binary} ->
        {records, valid_bytes} = decode_records(binary, [], 0)

        Enum.each(records, fn
          {:set, table_name, key, value, ts, ttl_ms}
          when is_binary(table_name) and is_binary(key) and is_integer(ts) ->
            entry = NewCacheEntry.from_wal(value, ts, ttl_ms)
            :ets.insert(table, {{table_name, key}, entry})

          {:delete, table_name, key, _ts} when is_binary(table_name) and is_binary(key) ->
            :ets.delete(table, {table_name, key})

          _ ->
            :ok
        end)

        if persist_truncate? and valid_bytes < byte_size(binary) do
          :ok = File.write(path, binary_part(binary, 0, valid_bytes))
        end

        :ok

      {:error, reason} ->
        if log_read_errors? do
          Logger.warning(
            "new_cache_rehydrate wal_read_failed path=#{path} reason=#{inspect(reason)}"
          )
        end

        :ok
    end
  end

  defp decode_records(<<len::unsigned-integer-size(32), rest::binary>>, acc, consumed)
       when byte_size(rest) >= len do
    <<term_bin::binary-size(len), tail::binary>> = rest

    case safe_binary_to_term(term_bin) do
      {:ok, term} -> decode_records(tail, [term | acc], consumed + 4 + len)
      :error -> {Enum.reverse(acc), consumed}
    end
  end

  defp decode_records(_binary, acc, consumed), do: {Enum.reverse(acc), consumed}

  defp safe_binary_to_term(binary) do
    {:ok, :erlang.binary_to_term(binary)}
  rescue
    _ -> :error
  end

  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :shard_id)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent
    }
  end
end
