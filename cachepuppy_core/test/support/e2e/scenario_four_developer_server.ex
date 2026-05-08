defmodule CachePuppy.Test.E2E.ScenarioFourDeveloperServer do
  @moduledoc """
  Scenario 4 flow (dynamic parallel with nested serial work before merge):
  start -> extract picks topics -> each branch performs research plus branch-local
  summarization work -> merge at compile -> store.

  This server validates that merge waits for full branch work, not partial progress.
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
      {"POST", "/summarise"} -> handle_summarise(conn, api_base)
      {"POST", "/compile"} -> handle_compile(conn, api_base)
      {"POST", "/store"} -> handle_store(conn)
      _ -> send_json(conn, 404, %{"error" => "not_found"})
    end
  end

  defp handle_start(conn, api_base) do
    with {:ok, payload, conn} <- decode_json(conn),
         paragraph when is_binary(paragraph) <- Map.get(payload, "paragraph"),
         workflow <- post_json!(api_base <> "/api/workflows", %{"name" => "e2e-scenario-4"}, 201),
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
         workflow_id when is_binary(workflow_id) <- input["workflowId"],
         paragraph when is_binary(paragraph) <- get_in(input, ["data", "paragraph"]) do
      jitter_sleep()
      topics = paragraph |> String.split() |> Enum.take(3)

      _ =
        post_json!(
          api_base <> "/api/workflows/" <> workflow_id <> "/parallel",
          %{
            "steps" =>
              topics
              |> Enum.with_index(1)
              |> Enum.map(fn {topic, idx} ->
                %{
                  "stepId" => "research_#{idx}",
                  "stepName" => "research",
                  "url" => base_url(conn) <> "/research",
                  "method" => "post",
                  "data" => %{
                    "topic" => topic,
                    "researchStepId" => "research_#{idx}",
                    "summariseStepId" => "summarise_#{idx}"
                  }
                }
              end),
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

      send_json(conn, 200, %{"topics" => topics})
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_extract_request"})
    end
  end

  defp handle_research(conn, api_base) do
    with {:ok, payload, conn} <- decode_json(conn),
         input when is_map(input) <- Map.get(payload, "input"),
         workflow_id when is_binary(workflow_id) <- input["workflowId"],
         topic when is_binary(topic) <- get_in(input, ["data", "topic"]),
         research_step_id when is_binary(research_step_id) <- get_in(input, ["data", "researchStepId"]),
         summarise_step_id when is_binary(summarise_step_id) <- get_in(input, ["data", "summariseStepId"]) do
      notes = "facts about #{topic}"

      _ =
        post_json!(
          api_base <> "/api/workflows/" <> workflow_id <> "/steps",
          %{
            "stepId" => summarise_step_id,
            "stepName" => "summarise",
            "url" => base_url(conn) <> "/summarise",
            "method" => "post",
            "parentIds" => [research_step_id],
            "data" => %{
              "topic" => topic,
              "notes" => notes,
              "researchStepId" => research_step_id,
              "summariseStepId" => summarise_step_id
            }
          },
          201
        )

      send_json(conn, 200, %{"topic" => topic, "notes" => notes})
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_research_request"})
    end
  end

  defp handle_summarise(conn, api_base) do
    with {:ok, payload, conn} <- decode_json(conn),
         input when is_map(input) <- Map.get(payload, "input"),
         workflow_id when is_binary(workflow_id) <- input["workflowId"],
         topic when is_binary(topic) <- get_in(input, ["data", "topic"]),
         notes when is_binary(notes) <- get_in(input, ["data", "notes"]),
         research_step_id when is_binary(research_step_id) <- get_in(input, ["data", "researchStepId"]),
         summarise_step_id when is_binary(summarise_step_id) <- get_in(input, ["data", "summariseStepId"]) do
      _ =
        post_json!(
          api_base <> "/api/workflows/" <> workflow_id <> "/parallel/close_branch",
          %{"branchId" => research_step_id, "terminalStepId" => summarise_step_id},
          200
        )

      send_json(conn, 200, %{"topic" => topic, "branchSummary" => "#{topic}: #{notes}"})
    else
      _ -> send_json(conn, 400, %{"error" => "invalid_summarise_request"})
    end
  end

  defp handle_compile(conn, api_base) do
    with {:ok, payload, conn} <- decode_json(conn),
         input when is_map(input) <- Map.get(payload, "input"),
         workflow_id when is_binary(workflow_id) <- input["workflowId"],
         merge_data when is_list(merge_data) <- Map.get(input, "mergeData") do
      compiled =
        merge_data
        |> Enum.map(& &1["output"]["branchSummary"])
        |> Enum.join(" | ")

      _ =
        post_json!(
          api_base <> "/api/workflows/" <> workflow_id <> "/steps",
          %{
            "stepName" => "store",
            "url" => base_url(conn) <> "/store",
            "method" => "post",
            "parentIds" => ["compile"],
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

  defp jitter_sleep, do: Process.sleep(Enum.random(@min_ai_delay_ms..@max_ai_delay_ms))

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
