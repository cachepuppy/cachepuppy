defmodule CachePuppyCore.Persistence.CacheRecoveryEngine do
  @moduledoc false

  require Logger

  alias CachePuppyCore.CacheConfig
  alias CachePuppyCore.Persistence.CacheUtils

  @spec load_snapshot_then_replay(non_neg_integer(), String.t()) :: :ets.tid()
  def load_snapshot_then_replay(shard_id, storage_dir) do
    table = load_snapshot_or_new(shard_id, storage_dir)
    checkpoint_seq = read_checkpoint_seq(storage_dir, shard_id)

    storage_dir
    |> CacheUtils.wal_segments(shard_id)
    |> Enum.filter(fn {seq, _, _} -> seq >= checkpoint_seq end)
    |> Enum.take(CacheConfig.recovery_max_segments())
    |> Enum.each(fn {_seq, path, _size} -> replay_wal_file(table, path) end)

    table
  end

  @spec read_checkpoint_seq(String.t(), non_neg_integer()) :: pos_integer()
  def read_checkpoint_seq(storage_dir, shard_id) do
    path = CacheUtils.checkpoint_path(storage_dir, shard_id)

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

  @spec truncate_corrupt_tail(binary()) :: {list(), non_neg_integer()}
  def truncate_corrupt_tail(binary), do: decode_records(binary, [], 0)

  defp load_snapshot_or_new(shard_id, storage_dir) do
    path = CacheUtils.snapshot_path(storage_dir, shard_id)

    case :ets.file2tab(String.to_charlist(path)) do
      {:ok, tid} ->
        Logger.info(
          "cache_rehydrate loaded_snapshot shard_id=#{shard_id} node=#{node()} path=#{path}"
        )

        tid

      {:error, reason} ->
        Logger.info(
          "cache_rehydrate cold_start shard_id=#{shard_id} node=#{node()} path=#{path} reason=#{inspect(reason)}"
        )

        :ets.new(__MODULE__, [:set, :protected])
    end
  end

  defp replay_wal_file(table, path) do
    case File.read(path) do
      {:ok, binary} ->
        {records, valid_bytes} = truncate_corrupt_tail(binary)

        Enum.each(records, fn
          {:set, table_name, key, value, _ts} when is_binary(table_name) and is_binary(key) ->
            :ets.insert(table, {{table_name, key}, value})

          _ ->
            :ok
        end)

        if valid_bytes < byte_size(binary) do
          :ok = File.write(path, binary_part(binary, 0, valid_bytes))
        end

      {:error, reason} ->
        Logger.warning("cache_rehydrate wal_read_failed path=#{path} reason=#{inspect(reason)}")
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
