defmodule CachePuppy.Test.StepServer do
  @moduledoc false

  import Plug.Conn

  @spec start(%{required(String.t()) => (map() -> {non_neg_integer(), map()})}) ::
          {:ok, String.t(), term()} | {:error, term()}
  def start(handlers) when is_map(handlers) do
    ref = {:cachepuppy_step_server, System.unique_integer([:positive, :monotonic])}

    case Plug.Cowboy.http(__MODULE__, [handlers: handlers], ref: ref, ip: {127, 0, 0, 1}, port: 0) do
      {:ok, _pid} ->
        {:ok, "http://127.0.0.1:#{:ranch.get_port(ref)}", ref}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec stop(term()) :: :ok
  def stop(ref) do
    Plug.Cowboy.shutdown(ref)
  end

  def init(opts), do: opts

  def call(conn, opts) do
    if conn.method == "POST" do
      route_post(conn, opts)
    else
      send_resp(conn, 404, Jason.encode!(%{error: "not_found"}))
    end
  end

  defp route_post(conn, opts) do
    handlers = Keyword.fetch!(opts, :handlers)
    step_name = conn |> get_req_header("x-cachepuppy-step") |> List.first()

    with true <- is_binary(step_name),
         handler when is_function(handler, 1) <- Map.get(handlers, step_name),
         {:ok, raw, conn} <- read_body(conn),
         {:ok, body} <- Jason.decode(raw) do
      input = Map.get(body, "input", %{})
      {status, response} = handler.(input)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(response))
    else
      false ->
        send_resp(conn, 400, Jason.encode!(%{error: "missing_step_header"}))

      nil ->
        send_resp(conn, 404, Jason.encode!(%{error: "unknown_step"}))

      {:error, _reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: "invalid_body"}))
    end
  end
end
