defmodule CachePuppyCore.Persistence.CacheWalReplay do
  @moduledoc false

  require Logger

  alias CachePuppyCore.Persistence.CacheEntry
  alias CachePuppyCore.Persistence.CacheUtils

  @spec truncate_corrupt_tail(binary()) :: {list(), non_neg_integer()}
  def truncate_corrupt_tail(binary), do: decode_records(binary, [], 0)

  @doc """
  Reads a WAL segment file, applies decoded records to the ETS table, and optionally
  truncates a corrupt tail on disk (recovery path).
  """
  @spec replay_wal_path_into_table(:ets.tid(), String.t(), keyword()) :: :ok
  def replay_wal_path_into_table(table, path, opts \\ []) do
    persist_truncate? = Keyword.get(opts, :persist_truncate, true)
    log_read_errors? = Keyword.get(opts, :log_read_errors, false)

    case File.read(path) do
      {:ok, binary} ->
        {records, valid_bytes} = truncate_corrupt_tail(binary)

        Enum.each(records, fn
          {:set, table_name, key, value, ts, ttl_ms}
          when is_binary(table_name) and is_binary(key) and is_integer(ts) ->
            entry = CacheEntry.from_wal(value, ts, ttl_ms)
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
          Logger.warning("cache_rehydrate wal_read_failed path=#{path} reason=#{inspect(reason)}")
        end

        :ok
    end
  end

  @doc """
  Builds `snapshot.ets` from the prior snapshot file (if any) plus WAL segments
  `[checkpoint_seq, included_seq]` inclusive. Does not mutate live shard ETS.
  """
  @spec materialize_snapshot_from_wal(String.t(), non_neg_integer(), pos_integer(), pos_integer()) ::
          :ok | {:error, term()}
  def materialize_snapshot_from_wal(storage_dir, shard_id, checkpoint_seq, included_seq) do
    base = load_snapshot_base_table(storage_dir, shard_id)

    try do
      segments =
        storage_dir
        |> CacheUtils.wal_segments(shard_id)
        |> Enum.filter(fn {seq, _, _} -> seq >= checkpoint_seq and seq <= included_seq end)
        |> Enum.sort_by(fn {seq, _, _} -> seq end)

      Enum.each(segments, fn {_seq, path, _size} ->
        replay_wal_path_into_table(base, path, persist_truncate: false)
      end)

      tmp_path = CacheUtils.snapshot_temp_path(storage_dir, shard_id)
      final_path = CacheUtils.snapshot_path(storage_dir, shard_id)
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

  defp load_snapshot_base_table(storage_dir, shard_id) do
    path = CacheUtils.snapshot_path(storage_dir, shard_id)

    case :ets.file2tab(String.to_charlist(path)) do
      {:ok, tid} ->
        tid

      {:error, _} ->
        :ets.new(__MODULE__, [:set, :private])
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
end
