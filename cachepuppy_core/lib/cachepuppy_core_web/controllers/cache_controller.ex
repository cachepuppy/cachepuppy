defmodule CachePuppyCoreWeb.CacheController do
  use CachePuppyCoreWeb, :controller

  alias CachePuppyCore.Persistence.CacheConfig
  alias CachePuppyCore.Persistence.CacheRouter

  def setdata(conn, %{"table" => table, "key" => key, "value" => value} = params)
      when is_binary(table) and is_binary(key) do
    with {:ok, opts} <- ttl_opts_from_params(params),
         {:ok, stored_value} <- CacheRouter.setdata(table, key, value, opts) do
      json(conn, %{"table" => table, "key" => key, "value" => stored_value})
    else
      {:error, :invalid_ttl} ->
        conn |> put_status(:bad_request) |> json(%{reason: "invalid_ttl_ms"})

      {:error, :invalid_table_or_key} ->
        conn |> put_status(:bad_request) |> json(%{reason: "invalid_table_or_key"})

      {:error, {:rpc_failed, _reason}} ->
        conn |> put_status(:service_unavailable) |> json(%{reason: "rpc_failed"})

      {:error, {:shard_unavailable, _reason}} ->
        conn |> put_status(:service_unavailable) |> json(%{reason: "shard_unavailable"})

      {:error, :rehydrating} ->
        conn |> put_status(:service_unavailable) |> json(%{reason: "rehydrating"})

      {:error, _reason} ->
        conn |> put_status(:internal_server_error) |> json(%{reason: "setdata_failed"})
    end
  end

  def setdata(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{reason: "invalid_payload"})
  end

  def getdata(conn, %{"table" => table, "key" => key}) when is_binary(table) and is_binary(key) do
    case CacheRouter.getdata(table, key) do
      {:ok, value} ->
        json(conn, %{"table" => table, "key" => key, "value" => value})

      {:error, :invalid_table_or_key} ->
        conn |> put_status(:bad_request) |> json(%{reason: "invalid_table_or_key"})

      {:error, {:rpc_failed, _reason}} ->
        conn |> put_status(:service_unavailable) |> json(%{reason: "rpc_failed"})

      {:error, {:shard_unavailable, _reason}} ->
        conn |> put_status(:service_unavailable) |> json(%{reason: "shard_unavailable"})

      {:error, :rehydrating} ->
        conn |> put_status(:service_unavailable) |> json(%{reason: "rehydrating"})

      {:error, _reason} ->
        conn |> put_status(:internal_server_error) |> json(%{reason: "getdata_failed"})
    end
  end

  def getdata(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{reason: "invalid_payload"})
  end

  def deletedata(conn, %{"table" => table, "key" => key})
      when is_binary(table) and is_binary(key) do
    case CacheRouter.deldata(table, key) do
      {:ok, deleted?} ->
        json(conn, %{"table" => table, "key" => key, "deleted" => deleted?})

      {:error, :invalid_table_or_key} ->
        conn |> put_status(:bad_request) |> json(%{reason: "invalid_table_or_key"})

      {:error, {:rpc_failed, _reason}} ->
        conn |> put_status(:service_unavailable) |> json(%{reason: "rpc_failed"})

      {:error, {:shard_unavailable, _reason}} ->
        conn |> put_status(:service_unavailable) |> json(%{reason: "shard_unavailable"})

      {:error, :rehydrating} ->
        conn |> put_status(:service_unavailable) |> json(%{reason: "rehydrating"})

      {:error, _reason} ->
        conn |> put_status(:internal_server_error) |> json(%{reason: "deletedata_failed"})
    end
  end

  def deletedata(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{reason: "invalid_payload"})
  end

  defp ttl_opts_from_params(params) do
    max = CacheConfig.ttl_ms_max()

    case Map.get(params, "ttl_ms") do
      nil ->
        {:ok, []}

      n when is_integer(n) and n > 0 ->
        if n <= max, do: {:ok, [ttl_ms: n]}, else: {:error, :invalid_ttl}

      _ ->
        {:error, :invalid_ttl}
    end
  end
end
