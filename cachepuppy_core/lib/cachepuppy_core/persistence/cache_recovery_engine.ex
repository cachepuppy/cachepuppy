defmodule CachePuppyCore.Persistence.CacheRecoveryEngine do
  @moduledoc false

  require Logger

  alias CachePuppyCore.CacheConfig
  alias CachePuppyCore.Persistence.CacheUtils
  alias CachePuppyCore.Persistence.CacheWalReplay

  @spec load_snapshot_then_replay(non_neg_integer(), String.t()) :: :ets.tid()
  def load_snapshot_then_replay(shard_id, storage_dir) do
    table = load_snapshot_or_new(shard_id, storage_dir)
    checkpoint_seq = read_checkpoint_seq(storage_dir, shard_id)

    storage_dir
    |> CacheUtils.wal_segments(shard_id)
    |> Enum.filter(fn {seq, _, _} -> seq >= checkpoint_seq end)
    |> Enum.take(CacheConfig.recovery_max_segments())
    |> Enum.each(fn {_seq, path, _size} ->
      CacheWalReplay.replay_wal_path_into_table(table, path,
        persist_truncate: true,
        log_read_errors: true
      )
    end)

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

  defdelegate truncate_corrupt_tail(binary), to: CacheWalReplay

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
end
