defmodule CachePuppyCoreWeb.CacheController do
  use CachePuppyCoreWeb, :controller

  alias CachePuppyCore.CacheRouter

  def setdata(conn, %{"table" => table, "key" => key, "value" => value})
      when is_binary(table) and is_binary(key) do
    case CacheRouter.setdata(table, key, value) do
      {:ok, stored_value} ->
        json(conn, %{"table" => table, "key" => key, "value" => stored_value})

      {:error, :invalid_table_or_key} ->
        conn |> put_status(:bad_request) |> json(%{reason: "invalid_table_or_key"})

      {:error, {:rpc_failed, _reason}} ->
        conn |> put_status(:service_unavailable) |> json(%{reason: "rpc_failed"})

      {:error, {:shard_unavailable, _reason}} ->
        conn |> put_status(:service_unavailable) |> json(%{reason: "shard_unavailable"})

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

      {:error, _reason} ->
        conn |> put_status(:internal_server_error) |> json(%{reason: "getdata_failed"})
    end
  end

  def getdata(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{reason: "invalid_payload"})
  end
end
