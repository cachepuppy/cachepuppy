defmodule CachePuppy.Test.E2E.ScenarioFiveDeveloperServer do
  @moduledoc """
  Scenario 5 flow (nested parallel fan-out with context-driven branch placement):
  start -> extract -> parallel research(A/B) -> per-branch nested search fan-out
  -> collect -> summarise -> outer merge_summaries -> store.
  """

  import Plug.Conn

  @min_ai_delay_ms 50
  @max_ai_delay_ms 300

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
      {"POST", "/research"} -> handle_research(conn, api_base)
      {"POST", "/search"} -> handle_search(conn)
      {"POST", "/collect"} -> handle_collect(conn, api_base)
      {"POST", "/summarise"} -> handle_summarise(conn, api_base)
      {"POST", "/merge_summaries"} -> handle_merge_summaries(conn, api_base)
      {"POST", "/store"} -> handle_store(conn)
      _ -> send_json(conn, 404, %{"error" => "not_found"})
    end
  end

  defp handle_start(conn, api_base) do
    with {:ok, payload, conn} <- decode_json(conn),
         paragraph when is_binary(paragraph) <- Map.get(payload, "paragraph"),
         workflow <- post_json!(api_base <> "/api/workflows", %{"name" => "e2e-scenario-5"}, 201),
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
      jitter_sleep()
      topics = ["A", "B"]

      _ =
        post_json!(
          api_base <> "/api/workflows/" <> workflow_id <> "/parallel",
          %{
            "steps" =>
              Enum.map(topics, fn topic ->
                %{
                  "stepId" => "research_#{String.downcase(topic)}",
                  "stepName" => "research",
                  "url" => base_url(conn) <> "/research",
                  "method" => "post",
                  "data" => %{"topic" => topic}
                }
              end),
            "mergeStep" => %{
              "stepId" => "merge_summaries",
              "stepName" => "merge_summaries",
              "url" => base_url(conn) <> "/merge_summaries",
              "method" => "post",
              "data" => %{}
            }
          },
          201
        )

      send_json(conn, 200, %{"topics" => topics})
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_extract_request"})
    end
  end

  defp handle_research(conn, api_base) do
    with {:ok, payload, conn} <- decode_json(conn),
         input when is_map(input) <- Map.get(payload, "input"),
         workflow_id when is_binary(workflow_id) <- input["workflowId"],
         research_step_id when is_binary(research_step_id) <- input["stepId"],
         topic when is_binary(topic) <- get_in(input, ["data", "topic"]) do
      base = String.replace_prefix(research_step_id, "research_", "")

      _ =
        post_json!(
          api_base <> "/api/workflows/" <> workflow_id <> "/parallel",
          %{
            "invokingStepId" => research_step_id,
            "steps" => [
              %{
                "stepId" => "search_#{base}_1",
                "stepName" => "search",
                "url" => base_url(conn) <> "/search",
                "method" => "post",
                "data" => %{"topic" => topic, "query" => "#{topic}-q1"}
              },
              %{
                "stepId" => "search_#{base}_2",
                "stepName" => "search",
                "url" => base_url(conn) <> "/search",
                "method" => "post",
                "data" => %{"topic" => topic, "query" => "#{topic}-q2"}
              }
            ],
            "mergeStep" => %{
              "stepId" => "collect_#{base}",
              "stepName" => "collect",
              "url" => base_url(conn) <> "/collect",
              "method" => "post",
              "data" => %{"topic" => topic}
            }
          },
          201
        )

      _ =
        post_json!(
          api_base <> "/api/workflows/" <> workflow_id <> "/parallel/merge_now",
          %{"mergeStepId" => "collect_#{base}"},
          200
        )

      send_json(conn, 200, %{"topic" => topic, "researchStepId" => research_step_id})
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_research_request"})
    end
  end

  defp handle_search(conn) do
    with {:ok, payload, conn} <- decode_json(conn),
         input when is_map(input) <- Map.get(payload, "input"),
         topic when is_binary(topic) <- get_in(input, ["data", "topic"]),
         query when is_binary(query) <- get_in(input, ["data", "query"]) do
      send_json(conn, 200, %{"topic" => topic, "result" => "result for #{query}"})
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_search_request"})
    end
  end

  defp handle_collect(conn, api_base) do
    with {:ok, payload, conn} <- decode_json(conn),
         input when is_map(input) <- Map.get(payload, "input"),
         workflow_id when is_binary(workflow_id) <- input["workflowId"],
         collect_step_id when is_binary(collect_step_id) <- input["stepId"],
         merge_data when is_list(merge_data) <- Map.get(input, "mergeData"),
         topic when is_binary(topic) <- get_in(input, ["data", "topic"]) do
      branch = String.replace_prefix(collect_step_id, "collect_", "")
      summary_step_id = "summarise_#{branch}"

      _ =
        post_json!(
          api_base <> "/api/workflows/" <> workflow_id <> "/steps",
          %{
            "invokingStepId" => collect_step_id,
            "stepId" => summary_step_id,
            "stepName" => "summarise",
            "url" => base_url(conn) <> "/summarise",
            "method" => "post",
            "data" => %{"topic" => topic, "resultsCount" => length(merge_data)}
          },
          201
        )

      send_json(conn, 200, %{"topic" => topic, "collected" => length(merge_data)})
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_collect_request"})
    end
  end

  defp handle_summarise(conn, api_base) do
    with {:ok, payload, conn} <- decode_json(conn),
         input when is_map(input) <- Map.get(payload, "input"),
         workflow_id when is_binary(workflow_id) <- input["workflowId"],
         topic when is_binary(topic) <- get_in(input, ["data", "topic"]),
         results_count when is_integer(results_count) <- get_in(input, ["data", "resultsCount"]) do
      _ =
        post_json!(
          api_base <> "/api/workflows/" <> workflow_id <> "/parallel/merge_now",
          %{"mergeStepId" => "merge_summaries"},
          200
        )

      send_json(conn, 200, %{"branchSummary" => "#{topic}:#{results_count}"})
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_summarise_request"})
    end
  end

  defp handle_merge_summaries(conn, api_base) do
    with {:ok, payload, conn} <- decode_json(conn),
         input when is_map(input) <- Map.get(payload, "input"),
         workflow_id when is_binary(workflow_id) <- input["workflowId"],
         merge_step_id when is_binary(merge_step_id) <- input["stepId"],
         merge_data when is_list(merge_data) <- Map.get(input, "mergeData") do
      merged =
        merge_data
        |> Enum.map(& &1["output"]["branchSummary"])
        |> Enum.join(" | ")

      _ =
        post_json!(
          api_base <> "/api/workflows/" <> workflow_id <> "/steps",
          %{
            "invokingStepId" => merge_step_id,
            "stepId" => "store",
            "stepName" => "store",
            "url" => base_url(conn) <> "/store",
            "method" => "post",
            "data" => %{"compiled" => merged}
          },
          201
        )

      send_json(conn, 200, %{"compiled" => merged})
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_merge_summaries_request"})
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

  defp jitter_sleep, do: Process.sleep(Enum.random(@min_ai_delay_ms..@max_ai_delay_ms))

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
