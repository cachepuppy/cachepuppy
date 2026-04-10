defmodule CachePuppyCoreWeb.UserSocket do
  use Phoenix.Socket

  channel "events:*", CachePuppyCoreWeb.EventChannel
  channel "session", CachePuppyCoreWeb.SessionChannel

  @impl true
  def connect(params, socket, _connect_info) do
    client_id =
      params
      |> Map.get("client_id")
      |> normalize_client_id()
      |> case do
        nil -> "anon_" <> Integer.to_string(System.unique_integer([:positive]))
        value -> value
      end

    {:ok, assign(socket, :client_id, client_id)}
  end

  @impl true
  def id(_socket), do: nil

  defp normalize_client_id(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      nil
    else
      String.slice(trimmed, 0, 64)
    end
  end

  defp normalize_client_id(_), do: nil
end
