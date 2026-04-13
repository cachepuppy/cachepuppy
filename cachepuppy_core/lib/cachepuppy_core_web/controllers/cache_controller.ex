defmodule CachePuppyCoreWeb.CacheController do
  use CachePuppyCoreWeb, :controller

  alias CachePuppyCore.CacheRouter

  def setdata(conn, %{"key" => key, "value" => value}) when is_binary(key) do
    case CacheRouter.setdata(key, value) do
      {:ok, stored_value} ->
        json(conn, %{"key" => key, "value" => stored_value})

      {:error, :invalid_key} ->
        conn |> put_status(:bad_request) |> json(%{reason: "invalid_key"})

      {:error, _reason} ->
        conn |> put_status(:internal_server_error) |> json(%{reason: "setdata_failed"})
    end
  end

  def setdata(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{reason: "invalid_payload"})
  end

  def getdata(conn, %{"key" => key}) when is_binary(key) do
    case CacheRouter.getdata(key) do
      {:ok, value} ->
        json(conn, %{"key" => key, "value" => value})

      {:error, :invalid_key} ->
        conn |> put_status(:bad_request) |> json(%{reason: "invalid_key"})

      {:error, _reason} ->
        conn |> put_status(:internal_server_error) |> json(%{reason: "getdata_failed"})
    end
  end

  def getdata(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{reason: "invalid_payload"})
  end
end
