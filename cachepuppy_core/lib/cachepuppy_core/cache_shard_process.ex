defmodule CachePuppyCore.CacheShardProcess do
  @moduledoc false

  use GenServer
  require Logger

  defmodule State do
    @moduledoc false
    defstruct shard_id: 0,
              table: nil,
              flush_interval_ms: 5_000,
              storage_dir: nil,
              owner_epoch: 0,
              dirty: false,
              flush_ref: nil
  end

  @default_flush_interval_ms 5_000
  @default_storage_dir "tmp/cache_shards"

  def child_spec(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)

    %{
      id: {__MODULE__, shard_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def start_link(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)
    name = Keyword.get(opts, :name, via_shard(shard_id))

    case name do
      nil -> GenServer.start_link(__MODULE__, opts)
      _ -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  def set(shard_id, table, key, value) when is_integer(shard_id) do
    GenServer.call(via_shard(shard_id), {:set, table, key, value})
  end

  def get(shard_id, table, key) when is_integer(shard_id) do
    GenServer.call(via_shard(shard_id), {:get, table, key})
  end

  @impl true
  def init(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)
    flush_interval_ms = Keyword.get(opts, :flush_interval_ms, @default_flush_interval_ms)
    storage_dir = Keyword.get(opts, :storage_dir, @default_storage_dir)
    _ = File.mkdir_p(storage_dir)
    owner_epoch = claim_ownership(shard_id, storage_dir)
    table = rehydrate_or_create_table(shard_id, storage_dir)

    state = %State{
      shard_id: shard_id,
      table: table,
      flush_interval_ms: flush_interval_ms,
      storage_dir: storage_dir,
      owner_epoch: owner_epoch
    }

    mark_rehydration_done(state)
    Logger.info(
      "cache_shard init shard_id=#{shard_id} node=#{node()} owner_epoch=#{owner_epoch} storage_dir=#{storage_dir}"
    )

    {:ok, schedule_flush(state)}
  end

  @impl true
  def handle_call({:set, table, key, value}, _from, state) when is_binary(table) and is_binary(key) do
    storage_key = {table, key}
    :ets.insert(state.table, {storage_key, value})
    Logger.info(
      "cache_set execute shard_id=#{state.shard_id} node=#{node()} table=#{inspect(table)} key=#{inspect(key)}"
    )

    {:reply, {:ok, value}, %{state | dirty: true}}
  end

  def handle_call({:set, _table, _key, _value}, _from, state) do
    {:reply, {:error, :invalid_table_or_key}, state}
  end

  @impl true
  def handle_call({:get, table, key}, _from, state) when is_binary(table) and is_binary(key) do
    storage_key = {table, key}

    value =
      case :ets.lookup(state.table, storage_key) do
        [{^storage_key, found}] -> found
        [] -> nil
      end

    Logger.info(
      "cache_get execute shard_id=#{state.shard_id} node=#{node()} table=#{inspect(table)} key=#{inspect(key)}"
    )

    {:reply, {:ok, value}, state}
  end

  def handle_call({:get, _table, _key}, _from, state) do
    {:reply, {:error, :invalid_table_or_key}, state}
  end

  @impl true
  def handle_info(:flush_tick, state) do
    state = %{state | flush_ref: nil}
    state = maybe_flush(state)
    {:noreply, schedule_flush(state)}
  end

  def maybe_flush(%State{dirty: false} = state), do: state

  def maybe_flush(state) do
    if current_owner?(state) do
      _ = File.mkdir_p(state.storage_dir)

      case :ets.tab2file(state.table, snapshot_path_charlist(state), sync: true) do
        :ok ->
          Logger.info(
            "cache_flush success shard_id=#{state.shard_id} node=#{node()} path=#{snapshot_path(state)}"
          )

          %{state | dirty: false}

        {:error, reason} ->
          Logger.warning(
            "cache_flush failed shard_id=#{state.shard_id} node=#{node()} reason=#{inspect(reason)}"
          )

          state
      end
    else
      Logger.info(
        "cache_flush skipped_stale_owner shard_id=#{state.shard_id} node=#{node()} owner_epoch=#{state.owner_epoch}"
      )

      state
    end
  end

  defp rehydrate_or_create_table(shard_id, storage_dir) do
    path = Path.join(storage_dir, "shard_#{shard_id}.ets")

    case :ets.file2tab(String.to_charlist(path)) do
      {:ok, tid} ->
        Logger.info("cache_rehydrate loaded shard_id=#{shard_id} node=#{node()} path=#{path}")
        tid

      {:error, reason} ->
        Logger.info(
          "cache_rehydrate cold_start shard_id=#{shard_id} node=#{node()} path=#{path} reason=#{inspect(reason)}"
        )

        :ets.new(__MODULE__, [:set, :protected])
    end
  end

  defp claim_ownership(shard_id, storage_dir) do
    meta = read_meta(storage_dir, shard_id)
    epoch = Map.get(meta, "epoch", 0) + 1
    persisted = base_meta(epoch, true)
    write_meta!(storage_dir, shard_id, persisted)
    epoch
  end

  defp mark_rehydration_done(%State{shard_id: shard_id, storage_dir: storage_dir, owner_epoch: epoch}) do
    meta = read_meta(storage_dir, shard_id)

    if Map.get(meta, "epoch") == epoch and Map.get(meta, "owner_node") == to_string(node()) do
      write_meta!(storage_dir, shard_id, base_meta(epoch, false))
    end
  end

  defp current_owner?(%State{shard_id: shard_id, storage_dir: storage_dir, owner_epoch: epoch}) do
    meta = read_meta(storage_dir, shard_id)

    Map.get(meta, "epoch") == epoch and
      Map.get(meta, "owner_node") == to_string(node()) and
      Map.get(meta, "rehydrating") == false
  end

  defp base_meta(epoch, rehydrating) do
    %{
      "epoch" => epoch,
      "owner_node" => to_string(node()),
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

  defp schedule_flush(%State{flush_interval_ms: interval_ms} = state) do
    ref = Process.send_after(self(), :flush_tick, interval_ms)
    %{state | flush_ref: ref}
  end

  defp snapshot_path(%State{storage_dir: storage_dir, shard_id: shard_id}) do
    Path.join(storage_dir, "shard_#{shard_id}.ets")
  end

  defp metadata_path(storage_dir, shard_id) do
    Path.join(storage_dir, "shard_#{shard_id}.meta")
  end

  defp snapshot_path_charlist(state) do
    state
    |> snapshot_path()
    |> String.to_charlist()
  end

  defp via_shard(shard_id) do
    {:via, Horde.Registry, {CachePuppyCore.CacheShardRegistry, shard_id}}
  end
end
