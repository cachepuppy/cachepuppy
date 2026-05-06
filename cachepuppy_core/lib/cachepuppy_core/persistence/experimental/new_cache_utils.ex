defmodule CachePuppyCore.Persistence.Experimental.NewCacheUtils do
  @moduledoc false

  @wal_pattern ~r/^shard_(\d+)\.wal\.(\d+)\.log$/

  @spec snapshot_path(String.t(), non_neg_integer()) :: String.t()
  def snapshot_path(storage_dir, shard_id) do
    Path.join(storage_dir, "shard_#{shard_id}.snapshot.ets")
  end

  @spec snapshot_temp_path(String.t(), non_neg_integer()) :: String.t()
  def snapshot_temp_path(storage_dir, shard_id) do
    snapshot_path(storage_dir, shard_id) <> ".tmp"
  end

  @spec checkpoint_path(String.t(), non_neg_integer()) :: String.t()
  def checkpoint_path(storage_dir, shard_id) do
    Path.join(storage_dir, "shard_#{shard_id}.wal.checkpoint")
  end

  @spec wal_path(String.t(), non_neg_integer(), pos_integer()) :: String.t()
  def wal_path(storage_dir, shard_id, seq) do
    Path.join(storage_dir, "shard_#{shard_id}.wal.#{seq}.log")
  end

  @spec wal_segments(String.t(), non_neg_integer()) :: [
          {pos_integer(), String.t(), non_neg_integer()}
        ]
  def wal_segments(storage_dir, shard_id) do
    storage_dir
    |> File.ls!()
    |> Enum.map(&parse_wal_name(&1, shard_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn {seq, file_name} ->
      path = Path.join(storage_dir, file_name)
      size = File.stat!(path).size
      {seq, path, size}
    end)
    |> Enum.sort_by(fn {seq, _, _} -> seq end)
  rescue
    _ -> []
  end

  defp parse_wal_name(file_name, shard_id) do
    case Regex.run(@wal_pattern, file_name) do
      [_, shard_str, seq_str] ->
        if String.to_integer(shard_str) == shard_id do
          {String.to_integer(seq_str), file_name}
        end

      _ ->
        nil
    end
  end
end
