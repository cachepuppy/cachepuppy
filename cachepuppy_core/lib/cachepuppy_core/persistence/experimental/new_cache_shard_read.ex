defmodule CachePuppyCore.Persistence.Experimental.NewCacheShardRead do
  @moduledoc false

  alias CachePuppyCore.Persistence.Experimental.NewCacheEntry

  @type shard_meta :: %{
          shard_id: non_neg_integer(),
          table: :ets.tid(),
          owner_epoch: non_neg_integer(),
          ready?: boolean(),
          owner_pid: pid()
        }

  @spec fast_get(non_neg_integer(), String.t(), String.t()) ::
          {:ok, term() | nil}
          | {:error, :invalid_table_or_key}
          | {:error, :rehydrating}
          | {:error, :shard_unavailable}
  def fast_get(shard_id, table, key)
      when is_integer(shard_id) and is_binary(table) and is_binary(key) do
    case :persistent_term.get(meta_key(shard_id), :undefined) do
      :undefined ->
        {:error, :shard_unavailable}

      %{ready?: false} ->
        {:error, :rehydrating}

      %{ready?: true, table: table_tid} ->
        lookup_value(table_tid, table, key)
    end
  end

  def fast_get(_shard_id, _table, _key), do: {:error, :invalid_table_or_key}

  @spec shard_meta(non_neg_integer()) :: shard_meta() | :undefined
  def shard_meta(shard_id) when is_integer(shard_id) do
    :persistent_term.get(meta_key(shard_id), :undefined)
  end

  @spec publish_rehydrating(non_neg_integer(), :ets.tid(), non_neg_integer()) :: :ok
  def publish_rehydrating(shard_id, table_tid, owner_epoch)
      when is_integer(shard_id) and is_reference(table_tid) and is_integer(owner_epoch) do
    :persistent_term.put(meta_key(shard_id), %{
      shard_id: shard_id,
      table: table_tid,
      owner_epoch: owner_epoch,
      ready?: false,
      owner_pid: self()
    })

    :ok
  end

  @spec publish_ready(non_neg_integer(), :ets.tid(), non_neg_integer()) :: :ok
  def publish_ready(shard_id, table_tid, owner_epoch)
      when is_integer(shard_id) and is_reference(table_tid) and is_integer(owner_epoch) do
    :persistent_term.put(meta_key(shard_id), %{
      shard_id: shard_id,
      table: table_tid,
      owner_epoch: owner_epoch,
      ready?: true,
      owner_pid: self()
    })

    :ok
  end

  @spec clear(pid()) :: :ok
  def clear(owner_pid) when is_pid(owner_pid) do
    prefix = {__MODULE__, :shard_meta}

    :persistent_term.get()
    |> Enum.each(fn
      {{^prefix, shard_id}, %{owner_pid: ^owner_pid}} ->
        :persistent_term.erase(meta_key(shard_id))

      _other ->
        :ok
    end)

    :ok
  end

  defp lookup_value(table_tid, table, key) do
    storage_key = {table, key}
    now = System.system_time(:millisecond)

    try do
      value =
        case :ets.lookup(table_tid, storage_key) do
          [{^storage_key, %NewCacheEntry{} = entry}] ->
            if is_integer(entry.expires_at_ms) and entry.expires_at_ms <= now do
              nil
            else
              entry.value
            end

          [] ->
            nil
        end

      {:ok, value}
    catch
      :error, :badarg -> {:error, :shard_unavailable}
    end
  end

  defp meta_key(shard_id), do: {{__MODULE__, :shard_meta}, shard_id}
end
