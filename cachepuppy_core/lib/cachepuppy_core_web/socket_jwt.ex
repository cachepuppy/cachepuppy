defmodule CachePuppyCoreWeb.SocketJwt do
  @moduledoc false

  @allowed_algs ["HS256"]

  @doc """
  Verifies a compact HS256 JWT using `secret`, checks `exp`, and returns the
  identity claim as a binary string (numbers are coerced with `trunc/1` then
  stringified). Returns `:error` on any failure.
  """
  @spec verify_identity(String.t(), String.t(), String.t()) :: {:ok, String.t()} | :error
  def verify_identity(token, secret, identity_claim)
      when is_binary(token) and is_binary(secret) and is_binary(identity_claim) do
    jwk = JOSE.JWK.from_oct(secret)

    case JOSE.JWT.verify_strict(jwk, @allowed_algs, token) do
      {true, %JOSE.JWT{fields: fields}, _jws} ->
        with true <- exp_valid?(fields),
             {:ok, identity} <- identity_from_claim(fields, identity_claim) do
          {:ok, identity}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  catch
    _, _ -> :error
  end

  def verify_identity(_, _, _), do: :error

  defp exp_valid?(fields) do
    now = System.system_time(:second)

    case Map.get(fields, "exp") do
      exp when is_integer(exp) -> exp > now
      exp when is_float(exp) -> trunc(exp) > now
      _ -> false
    end
  end

  defp identity_from_claim(fields, claim_key) do
    case Map.get(fields, claim_key) do
      nil -> :error
      val when is_binary(val) -> {:ok, val}
      val when is_integer(val) -> {:ok, Integer.to_string(val)}
      val when is_float(val) -> {:ok, val |> trunc() |> Integer.to_string()}
      _ -> :error
    end
  end
end
