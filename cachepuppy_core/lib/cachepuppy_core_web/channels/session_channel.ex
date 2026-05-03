defmodule CachePuppyCoreWeb.SessionChannel do
  @moduledoc false

  use CachePuppyCoreWeb, :channel
  alias CachePuppyCore.Persistence.CacheConfig
  alias CachePuppyCore.Persistence.CacheRouter

  @impl true
  def join("session", _payload, %{assigns: %{client_id: client_id}} = socket) do
    socket = assign(socket, :session_state, %{})
    {:ok, %{"connected_node" => to_string(node()), "client_id" => client_id}, socket}
  end

  @impl true
  def handle_in("set_session_state", %{"payload" => payload}, socket) when is_map(payload) do
    socket = assign(socket, :session_state, payload)
    {:reply, {:ok, %{"state" => payload}}, socket}
  end

  @impl true
  def handle_in("set_session_state", %{"payload" => _payload}, socket) do
    {:reply, {:error, %{reason: "invalid_payload"}}, socket}
  end

  @impl true
  def handle_in("get_session_state", _payload, socket) do
    session_state = Map.get(socket.assigns, :session_state, %{})
    {:reply, {:ok, %{"state" => session_state}}, socket}
  end

  @impl true
  def handle_in(
        "set_cache_data",
        %{"table" => table, "key" => key, "value" => value} = payload,
        socket
      )
      when is_binary(table) and is_binary(key) do
    with {:ok, opts} <- ttl_opts_from_payload(payload),
         {:ok, stored_value} <- CacheRouter.setdata(table, key, value, opts) do
      {:reply, {:ok, %{"table" => table, "key" => key, "value" => stored_value}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: map_cache_error_reason(reason)}}, socket}
    end
  end

  def handle_in("set_cache_data", _payload, socket) do
    {:reply, {:error, %{reason: "invalid_payload"}}, socket}
  end

  @impl true
  def handle_in("get_cache_data", %{"table" => table, "key" => key}, socket)
      when is_binary(table) and is_binary(key) do
    case CacheRouter.getdata(table, key) do
      {:ok, value} ->
        {:reply, {:ok, %{"table" => table, "key" => key, "value" => value}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: map_cache_error_reason(reason)}}, socket}
    end
  end

  def handle_in("get_cache_data", _payload, socket) do
    {:reply, {:error, %{reason: "invalid_payload"}}, socket}
  end

  @impl true
  def handle_in(
        "update_cache_data",
        %{"table" => table, "key" => key, "patch" => patch} = payload,
        socket
      )
      when is_binary(table) and is_binary(key) and is_map(patch) do
    with {:ok, opts} <- ttl_opts_from_payload(payload),
         {:ok, stored_value} <- CacheRouter.updatedata(table, key, patch, opts) do
      {:reply, {:ok, %{"table" => table, "key" => key, "value" => stored_value}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: map_cache_error_reason(reason)}}, socket}
    end
  end

  def handle_in("update_cache_data", _payload, socket) do
    {:reply, {:error, %{reason: "invalid_payload"}}, socket}
  end

  @impl true
  def handle_in("delete_cache_data", %{"table" => table, "key" => key}, socket)
      when is_binary(table) and is_binary(key) do
    case CacheRouter.deldata(table, key) do
      {:ok, deleted?} ->
        {:reply, {:ok, %{"table" => table, "key" => key, "deleted" => deleted?}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: map_cache_error_reason(reason)}}, socket}
    end
  end

  def handle_in("delete_cache_data", _payload, socket) do
    {:reply, {:error, %{reason: "invalid_payload"}}, socket}
  end

  @impl true
  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "unsupported_event"}}, socket}
  end

  defp ttl_opts_from_payload(payload) do
    max = CacheConfig.ttl_ms_max()

    case Map.get(payload, "ttl_ms") do
      nil ->
        {:ok, []}

      n when is_integer(n) and n > 0 and n <= max ->
        {:ok, [ttl_ms: n]}

      _ ->
        {:error, :invalid_ttl}
    end
  end

  defp map_cache_error_reason(:invalid_ttl), do: "invalid_ttl_ms"
  defp map_cache_error_reason(:invalid_patch), do: "invalid_patch"
  defp map_cache_error_reason(:value_not_mergeable), do: "value_not_mergeable"
  defp map_cache_error_reason(:not_found), do: "not_found"
  defp map_cache_error_reason(:invalid_table_or_key), do: "invalid_table_or_key"
  defp map_cache_error_reason(:rehydrating), do: "rehydrating"
  defp map_cache_error_reason({:rpc_failed, _reason}), do: "rpc_failed"
  defp map_cache_error_reason({:shard_unavailable, _reason}), do: "shard_unavailable"
  defp map_cache_error_reason(_reason), do: "cache_operation_failed"
end
