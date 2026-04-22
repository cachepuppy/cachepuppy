defmodule CachePuppyCoreWeb.UserSocket do
  use Phoenix.Socket

  channel "events:*", CachePuppyCoreWeb.EventChannel
  channel "session", CachePuppyCoreWeb.SessionChannel

  @impl true
  def connect(params, socket, _connect_info) do
    if Application.get_env(:cachepuppy_core, :websocket_auth_enabled, false) do
      connect_authenticated(params, socket)
    else
      connect_unauthenticated(params, socket)
    end
  end

  @impl true
  def id(_socket), do: nil

  defp connect_unauthenticated(params, socket) do
    client_id =
      params
      |> client_id_from_params()
      |> normalize_client_id()
      |> case do
        nil -> "anon_" <> Integer.to_string(System.unique_integer([:positive]))
        value -> value
      end

    {:ok, assign(socket, :client_id, client_id)}
  end

  defp connect_authenticated(params, socket) do
    secret = Application.fetch_env!(:cachepuppy_core, :websocket_jwt_secret)
    identity_claim = Application.fetch_env!(:cachepuppy_core, :websocket_jwt_identity_claim)

    with {:ok, client_id} <- require_explicit_client_id(params),
         {:ok, token} <- require_token(params),
         {:ok, claim_raw} <-
           CachePuppyCoreWeb.SocketJwt.verify_identity(token, secret, identity_claim),
         {:ok, ^client_id} <- normalized_identity_match(client_id, claim_raw) do
      {:ok, assign(socket, :client_id, client_id)}
    else
      _ -> :error
    end
  end

  defp require_explicit_client_id(params) do
    case params |> client_id_from_params() |> normalize_client_id() do
      nil -> :error
      id -> {:ok, id}
    end
  end

  defp require_token(params) do
    case param_token(params) do
      t when is_binary(t) ->
        trimmed = String.trim(t)

        if trimmed == "" do
          :error
        else
          {:ok, trimmed}
        end

      _ ->
        :error
    end
  end

  defp normalized_identity_match(client_id, claim_raw) do
    case normalize_client_id(claim_raw) do
      ^client_id -> {:ok, client_id}
      _ -> :error
    end
  end

  defp client_id_from_params(params) do
    Map.get(params, "client_id") || Map.get(params, :client_id)
  end

  defp param_token(params) do
    Map.get(params, "token") || Map.get(params, :token)
  end

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
