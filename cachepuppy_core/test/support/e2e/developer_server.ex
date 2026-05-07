defmodule CachePuppy.Test.E2E.DeveloperServer do
  @moduledoc false

  import Plug.Conn

  @spec start(%{required(String.t()) => (map() -> {non_neg_integer(), map()})}) ::
          {:ok, String.t(), reference()} | {:error, term()}
  def start(handlers) when is_map(handlers) do
    ref = make_ref()

    case Plug.Cowboy.http(__MODULE__, [handlers: handlers], ref: ref, ip: {127, 0, 0, 1}, port: 0) do
      {:ok, _pid} -> {:ok, "http://127.0.0.1:#{:ranch.get_port(ref)}", ref}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec stop(reference()) :: :ok
  def stop(ref), do: Plug.Cowboy.shutdown(ref)

  def init(opts), do: opts

  def call(conn, opts) do
    handlers = Keyword.fetch!(opts, :handlers)
    step_name = conn |> get_req_header("x-cachepuppy-step") |> List.first()

    with "POST" <- conn.method,
         true <- is_binary(step_name),
         handler when is_function(handler, 1) <- Map.get(handlers, step_name),
         {:ok, body, conn} <- read_body(conn),
         {:ok, payload} <- Jason.decode(body) do
      {status, response} = handler.(Map.get(payload, "input", %{}))

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(response))
    else
      _ -> send_resp(conn, 400, Jason.encode!(%{"error" => "invalid_request"}))
    end
  end
end
