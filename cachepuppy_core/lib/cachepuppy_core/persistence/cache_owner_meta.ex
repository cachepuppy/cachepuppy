defmodule CachePuppyCore.Persistence.CacheOwnerMeta do
  @moduledoc false

  @spec claim_ownership(String.t(), non_neg_integer(), String.t()) :: non_neg_integer()
  def claim_ownership(storage_dir, shard_id, owner_node) do
    meta = read_meta(storage_dir, shard_id)
    epoch = Map.get(meta, "epoch", 0) + 1
    write_meta!(storage_dir, shard_id, base_meta(epoch, owner_node, true))
    epoch
  end

  @spec mark_rehydration_done(String.t(), non_neg_integer(), non_neg_integer(), String.t()) :: :ok
  def mark_rehydration_done(storage_dir, shard_id, epoch, owner_node) do
    meta = read_meta(storage_dir, shard_id)

    if Map.get(meta, "epoch") == epoch and Map.get(meta, "owner_node") == owner_node do
      write_meta!(storage_dir, shard_id, base_meta(epoch, owner_node, false))
    end

    :ok
  end

  @spec owner_valid?(String.t(), non_neg_integer(), non_neg_integer(), String.t()) :: boolean()
  def owner_valid?(storage_dir, shard_id, epoch, owner_node) do
    meta = read_meta(storage_dir, shard_id)

    Map.get(meta, "epoch") == epoch and
      Map.get(meta, "owner_node") == owner_node and
      Map.get(meta, "rehydrating") == false
  end

  @spec claim_holder?(String.t(), non_neg_integer(), non_neg_integer(), String.t()) :: boolean()
  def claim_holder?(storage_dir, shard_id, epoch, owner_node) do
    meta = read_meta(storage_dir, shard_id)

    Map.get(meta, "epoch") == epoch and Map.get(meta, "owner_node") == owner_node
  end

  defp base_meta(epoch, owner_node, rehydrating) do
    %{
      "epoch" => epoch,
      "owner_node" => owner_node,
      "rehydrating" => rehydrating,
      "updated_at_ms" => System.system_time(:millisecond)
    }
  end

  defp read_meta(storage_dir, shard_id) do
    path = metadata_path(storage_dir, shard_id)

    case File.read(path) do
      {:ok, binary} ->
        case :erlang.binary_to_term(binary) do
          meta when is_map(meta) -> meta
          _ -> %{}
        end

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  defp write_meta!(storage_dir, shard_id, meta) do
    path = metadata_path(storage_dir, shard_id)
    tmp_path = path <> ".tmp"
    :ok = File.write(tmp_path, :erlang.term_to_binary(meta))
    :ok = File.rename(tmp_path, path)
  end

  defp metadata_path(storage_dir, shard_id) do
    Path.join(storage_dir, "shard_#{shard_id}.meta")
  end
end
