defmodule CachePuppy.Test.E2E.ScenarioSevenDeveloperServer do
  @moduledoc """
  E2E scenario 7: two parallel branches fail HTTP until executor gives up, then recover via
  `POST /api/workflows/:id/retry_failed_steps`.
  """

  import Plug.Conn

  @attempts_table :cachepuppy_e2e_scenario7_attempts

  @spec start(keyword()) :: {:ok, String.t(), reference()} | {:error, term()}
  def start(opts) do
    api_base = Keyword.fetch!(opts, :api_base)
    ref = make_ref()
    ensure_attempts_table()

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
      {"POST", "/branch_a"} -> handle_branch(conn, "branch_a")
      {"POST", "/branch_b"} -> handle_branch(conn, "branch_b")
      {"POST", "/compile"} -> handle_compile(conn, api_base)
      {"POST", "/store"} -> handle_store(conn)
      _ -> send_json(conn, 404, %{"error" => "not_found"})
    end
  end

  defp handle_start(conn, api_base) do
    with {:ok, payload, conn} <- decode_json(conn),
         paragraph when is_binary(paragraph) <- Map.get(payload, "paragraph"),
         workflow <-
           post_json!(api_base <> "/api/workflows", %{"name" => "e2e-scenario-7"}, 201),
         workflow_id when is_binary(workflow_id) <- workflow["workflowId"],
         _ <-
           post_json!(
             api_base <> "/api/workflows/" <> workflow_id <> "/steps",
             %{
               "stepId" => "extract",
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
      parallel_created =
        post_json!(
          api_base <> "/api/workflows/" <> workflow_id <> "/parallel",
          %{
            "steps" => [
              %{
                "stepId" => "branch_a",
                "stepName" => "branch_a",
                "url" => base_url(conn) <> "/branch_a",
                "method" => "post",
                "maxRetries" => 0,
                "data" => %{}
              },
              %{
                "stepId" => "branch_b",
                "stepName" => "branch_b",
                "url" => base_url(conn) <> "/branch_b",
                "method" => "post",
                "maxRetries" => 0,
                "data" => %{}
              }
            ],
            "mergeStep" => %{
              "stepId" => "compile",
              "stepName" => "compile",
              "url" => base_url(conn) <> "/compile",
              "method" => "post",
              "data" => %{}
            }
          },
          201
        )

      _ =
        post_json!(
          api_base <> "/api/workflows/" <> workflow_id <> "/parallel/merge_now",
          %{"mergeStepId" => get_in(parallel_created, ["mergeStep", "stepId"])},
          200
        )

      send_json(conn, 200, %{"keywords" => ["a", "b"]})
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_extract_request"})
    end
  end

  defp handle_branch(conn, step_id) do
    with {:ok, payload, conn} <- decode_json(conn),
         input when is_map(input) <- Map.get(payload, "input"),
         workflow_id when is_binary(workflow_id) <- input["workflowId"] do
      attempts = increment_attempt(workflow_id, step_id)

      if attempts <= 4 do
        send_json(conn, 500, %{"error" => "branch_fail"})
      else
        send_json(conn, 200, %{"result" => "#{step_id}_ok"})
      end
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_branch_request"})
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
            "stepId" => "store",
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

  defp ensure_attempts_table do
    case :ets.whereis(@attempts_table) do
      :undefined -> :ets.new(@attempts_table, [:named_table, :public, :set])
      _ -> :ok
    end
  end

  defp increment_attempt(workflow_id, step_id) do
    key = {workflow_id, step_id}
    :ets.update_counter(@attempts_table, key, {2, 1}, {key, 0})
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
      {:ok, %{status: ^expected_status, body: body}} when is_map(body) ->
        body

      {:ok, %{status: status, body: body}} ->
        raise "POST #{url} expected #{expected_status}, got #{status}: #{inspect(body)}"

      {:error, reason} ->
        raise "POST #{url} failed: #{inspect(reason)}"
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
