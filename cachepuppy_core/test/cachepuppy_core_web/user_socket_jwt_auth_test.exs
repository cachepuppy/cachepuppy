defmodule CachePuppyCoreWeb.UserSocketJwtAuthTest do
  use ExUnit.Case, async: false

  @endpoint CachePuppyCoreWeb.Endpoint

  @secret "test_socket_jwt_secret_value_12345"

  setup do
    prev = %{
      enabled: Application.get_env(:cachepuppy_core, :websocket_auth_enabled),
      secret: Application.get_env(:cachepuppy_core, :websocket_jwt_secret),
      claim: Application.get_env(:cachepuppy_core, :websocket_jwt_identity_claim)
    }

    on_exit(fn ->
      Application.put_env(:cachepuppy_core, :websocket_auth_enabled, prev.enabled)
      Application.put_env(:cachepuppy_core, :websocket_jwt_secret, prev.secret)
      Application.put_env(:cachepuppy_core, :websocket_jwt_identity_claim, prev.claim)
    end)

    {:ok, prev: prev}
  end

  defp base_socket do
    %Phoenix.Socket{
      endpoint: @endpoint,
      handler: CachePuppyCoreWeb.UserSocket
    }
  end

  defp connect(params) do
    CachePuppyCoreWeb.UserSocket.connect(params, base_socket(), %{})
  end

  defp put_auth!(enabled, secret, claim) do
    Application.put_env(:cachepuppy_core, :websocket_auth_enabled, enabled)
    Application.put_env(:cachepuppy_core, :websocket_jwt_secret, secret)
    Application.put_env(:cachepuppy_core, :websocket_jwt_identity_claim, claim)
  end

  defp sign_jwt(secret, claims) when is_map(claims) do
    jwk = JOSE.JWK.from_oct(secret)

    JOSE.JWT.sign(jwk, %{"alg" => "HS256"}, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  test "auth disabled: connect succeeds without token", %{prev: prev} do
    put_auth!(false, nil, prev.claim || "sub")

    assert {:ok, socket} = connect(%{"client_id" => "plain_client"})
    assert socket.assigns.client_id == "plain_client"
  end

  test "auth disabled: junk token is ignored", %{prev: prev} do
    put_auth!(false, nil, prev.claim || "sub")

    assert {:ok, socket} =
             connect(%{"client_id" => "plain_client", "token" => "not.valid.jwt"})

    assert socket.assigns.client_id == "plain_client"
  end

  test "auth enabled: valid token and matching client_id", %{prev: _} do
    put_auth!(true, @secret, "sub")
    cid = "jwt_client_alpha"
    exp = System.system_time(:second) + 3600
    token = sign_jwt(@secret, %{"sub" => cid, "exp" => exp})

    assert {:ok, socket} = connect(%{"client_id" => cid, "token" => token})
    assert socket.assigns.client_id == cid
  end

  test "auth enabled: mismatched client_id vs claim", %{prev: _} do
    put_auth!(true, @secret, "sub")
    exp = System.system_time(:second) + 3600
    token = sign_jwt(@secret, %{"sub" => "token_identity", "exp" => exp})

    assert :error = connect(%{"client_id" => "sdk_identity", "token" => token})
  end

  test "auth enabled: invalid token", %{prev: _} do
    put_auth!(true, @secret, "sub")

    assert :error =
             connect(%{"client_id" => "any_client", "token" => "completely-invalid"})
  end

  test "auth enabled: expired token", %{prev: _} do
    put_auth!(true, @secret, "sub")
    cid = "expired_client"
    exp = System.system_time(:second) - 10
    token = sign_jwt(@secret, %{"sub" => cid, "exp" => exp})

    assert :error = connect(%{"client_id" => cid, "token" => token})
  end

  test "auth enabled: missing token", %{prev: _} do
    put_auth!(true, @secret, "sub")

    assert :error = connect(%{"client_id" => "no_token_client"})
  end

  test "auth enabled: missing client_id", %{prev: _} do
    put_auth!(true, @secret, "sub")
    exp = System.system_time(:second) + 3600
    token = sign_jwt(@secret, %{"sub" => "some_sub", "exp" => exp})

    assert :error = connect(%{"token" => token})
  end

  test "auth enabled: custom JWT_IDENTITY_CLAIM value", %{prev: _} do
    put_auth!(true, @secret, "client_ref")
    cid = "custom_claim_client"
    exp = System.system_time(:second) + 3600
    token = sign_jwt(@secret, %{"client_ref" => cid, "sub" => "ignored", "exp" => exp})

    assert {:ok, socket} = connect(%{"client_id" => cid, "token" => token})
    assert socket.assigns.client_id == cid
  end
end
