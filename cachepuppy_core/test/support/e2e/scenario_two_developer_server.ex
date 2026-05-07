defmodule CachePuppy.Test.E2E.ScenarioTwoDeveloperServer do
  @moduledoc false

  import Plug.Conn

  @spec start(keyword()) :: {:ok, String.t(), reference()} | {:error, term()}
  def start(opts) do
    api_base = Keyword.fetch!(opts, :api_base)
    ref = make_ref()

    case Plug.Cowboy.http(__MODULE__, [api_base: api_base], ref: ref, ip: {127, 0, 0, 1}, port: 0) do
      {:ok, _pid} ->
        {:ok, "http://127.0.0.1:#{:ranch.get_port(ref)}", ref}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec stop(reference()) :: :ok
  def stop(ref), do: Plug.Cowboy.shutdown(ref)

  def init(opts), do: opts

  def call(conn, opts) do
    api_base = Keyword.fetch!(opts, :api_base)

    case {conn.method, conn.request_path} do
      {"POST", "/start"} -> handle_start(conn, api_base)
      {"POST", "/extract"} -> handle_extract(conn, api_base)
      {"POST", "/research_A"} -> handle_research(conn, "A")
      {"POST", "/research_B"} -> handle_research(conn, "B")
      {"POST", "/research_C"} -> handle_research(conn, "C")
      {"POST", "/compile"} -> handle_compile(conn, api_base)
      {"POST", "/store"} -> handle_store(conn)
      _ -> send_json(conn, 404, %{"error" => "not_found"})
    end
  end

  defp handle_start(conn, api_base) do
    with {:ok, payload, conn} <- decode_json(conn),
         paragraph when is_binary(paragraph) <- Map.get(payload, "paragraph"),
         workflow <- post_json!(api_base <> "/api/workflows", %{"name" => "e2e-scenario-2"}, 201),
         workflow_id when is_binary(workflow_id) <- workflow["workflowId"],
         _ <-
           post_json!(
             api_base <> "/api/workflows/" <> workflow_id <> "/steps",
             %{
               "stepName" => "extract",
               "url" => base_url(conn) <> "/extract",
               "method" => "post",
               "data" => %{"paragraph" => paragraph}
             },
             201
           ) do
      send_json(conn, 201, %{"workflowId" => workflow_id})
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_start_request"})
    end
  end

  defp handle_extract(conn, api_base) do
    with {:ok, payload, conn} <- decode_json(conn),
         input when is_map(input) <- Map.get(payload, "input"),
         workflow_id when is_binary(workflow_id) <- input["workflowId"] do
      _ =
        post_json!(
          api_base <> "/api/workflows/" <> workflow_id <> "/parallel",
          %{
            "steps" => [
              %{"stepName" => "research_A", "url" => base_url(conn) <> "/research_A", "method" => "post", "data" => %{"keyword" => "alpha"}},
              %{"stepName" => "research_B", "url" => base_url(conn) <> "/research_B", "method" => "post", "data" => %{"keyword" => "beta"}},
              %{"stepName" => "research_C", "url" => base_url(conn) <> "/research_C", "method" => "post", "data" => %{"keyword" => "gamma"}}
            ]
          },
          201
        )

      _ =
        post_json!(
          api_base <> "/api/workflows/" <> workflow_id <> "/merge",
          %{"stepName" => "compile", "url" => base_url(conn) <> "/compile", "method" => "post", "data" => %{}},
          201
        )

      send_json(conn, 200, %{"keywords" => ["alpha", "beta", "gamma"]})
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_extract_request"})
    end
  end

  defp handle_research(conn, branch) do
    with {:ok, payload, conn} <- decode_json(conn),
         input when is_map(input) <- Map.get(payload, "input"),
         keyword when is_binary(keyword) <- get_in(input, ["data", "keyword"]) do
      send_json(conn, 200, %{"branch" => branch, "result" => "res:#{keyword}"})
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_research_request"})
    end
  end

  defp handle_compile(conn, api_base) do
    with {:ok, payload, conn} <- decode_json(conn),
         input when is_map(input) <- Map.get(payload, "input"),
         workflow_id when is_binary(workflow_id) <- input["workflowId"],
         merge_data when is_list(merge_data) <- Map.get(input, "mergeData") do
      compiled =
        merge_data
        |> Enum.map(& &1["output"]["result"])
        |> Enum.join(", ")

      _ =
        post_json!(
          api_base <> "/api/workflows/" <> workflow_id <> "/steps",
          %{
            "stepName" => "store",
            "url" => base_url(conn) <> "/store",
            "method" => "post",
            "data" => %{"compiled" => compiled}
          },
          201
        )

      send_json(conn, 200, %{"compiled" => compiled})
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_compile_request"})
    end
  end

  defp handle_store(conn) do
    with {:ok, payload, conn} <- decode_json(conn),
         input when is_map(input) <- Map.get(payload, "input"),
         compiled when is_binary(compiled) <- get_in(input, ["data", "compiled"]) do
      send_json(conn, 200, %{"stored" => true, "compiledLength" => String.length(compiled)})
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_store_request"})
    end
  end

  defp base_url(conn), do: "#{conn.scheme}://#{conn.host}:#{conn.port}"

  defp decode_json(conn) do
    with {:ok, raw, conn} <- read_body(conn),
         {:ok, payload} <- Jason.decode(raw) do
      {:ok, payload, conn}
    end
  end

  defp post_json!(url, payload, expected_status) do
    case Req.post(url, json: payload) do
      {:ok, %{status: ^expected_status, body: body}} when is_map(body) -> body
      {:ok, %{status: status, body: body}} -> raise "POST #{url} expected #{expected_status}, got #{status}: #{inspect(body)}"
      {:error, reason} -> raise "POST #{url} failed: #{inspect(reason)}"
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
