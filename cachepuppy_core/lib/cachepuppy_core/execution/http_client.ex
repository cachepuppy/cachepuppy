defmodule CachePuppyCore.Execution.HttpClient do
  @moduledoc false

  @type ok_response :: %{status: non_neg_integer(), body: term()}
  @type error_reason ::
          {:timeout, String.t()}
          | {:connection_error, String.t()}

  @spec post_step(String.t(), map(), [{String.t(), String.t()}], keyword()) ::
          {:ok, ok_response()} | {:error, error_reason()}
  def post_step(url, body_map, headers, opts) when is_binary(url) and is_map(body_map) do
    timeout = Keyword.fetch!(opts, :receive_timeout)
    finch = Keyword.get(opts, :finch, CachePuppyCore.Finch)

    req_opts = [
      finch: finch,
      json: body_map,
      headers: headers,
      receive_timeout: timeout
    ]

    case Req.post(url, req_opts) do
      {:ok, %Req.Response{status: status, body: body}} ->
        {:ok, %{status: status, body: body}}

      {:error, exception} ->
        {:error, normalize_error(exception)}
    end
  end

  defp normalize_error(%Req.TransportError{reason: reason} = e) do
    msg = Exception.message(e)

    case reason do
      :timeout ->
        {:timeout, msg}

      :connect_timeout ->
        {:timeout, msg}

      _ ->
        {:connection_error, msg}
    end
  end

  defp normalize_error(other) do
    {:connection_error, Exception.message(other)}
  end
end
