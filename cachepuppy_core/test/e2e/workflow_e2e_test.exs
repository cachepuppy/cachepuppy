defmodule CachePuppyCore.E2E.WorkflowE2ETest do
  use ExUnit.Case, async: false

  alias CachePuppy.Test.E2E.Assertions
  alias CachePuppy.Test.E2E.ScenarioFiveDeveloperServer
  alias CachePuppy.Test.E2E.ScenarioFourDeveloperServer
  alias CachePuppy.Test.E2E.ScenarioOneDeveloperServer
  alias CachePuppy.Test.E2E.ScenarioThreeDeveloperServer
  alias CachePuppy.Test.E2E.ScenarioTwoDeveloperServer
  alias CachePuppyCore.Workflow.WorkflowStore

  setup_all do
    ref = {:cachepuppy_http_e2e, System.unique_integer([:positive, :monotonic])}

    {:ok, _pid} =
      Plug.Cowboy.http(CachePuppyCoreWeb.Endpoint, [], ref: ref, ip: {127, 0, 0, 1}, port: 0)

    api_base = "http://127.0.0.1:#{:ranch.get_port(ref)}"
    on_exit(fn -> Plug.Cowboy.shutdown(ref) end)
    {:ok, api_base: api_base}
  end

  test "scenario 1 - serial extract -> research -> compile -> store", %{api_base: api_base} do
    {:ok, dev_base, dev_ref} = ScenarioOneDeveloperServer.start(api_base: api_base)
    on_exit(fn -> ScenarioOneDeveloperServer.stop(dev_ref) end)

    start_response =
      post_json!(dev_base <> "/start", %{
        "paragraph" => "cachepuppy workflows behave like production systems"
      })

    workflow_id = start_response["workflowId"]
    assert is_binary(workflow_id)
    on_exit(fn -> WorkflowStore.delete(workflow_id) end)

    workflow = Assertions.wait_for_completion(api_base, workflow_id, timeout_ms: 15_000)

    assert workflow["status"] == "completed"
    assert Enum.all?(workflow["steps"], &(&1["status"] == "completed"))

    extract = Enum.find(workflow["steps"], &(&1["stepName"] == "extract"))
    research = Enum.find(workflow["steps"], &(&1["stepName"] == "research"))
    compile = Enum.find(workflow["steps"], &(&1["stepName"] == "compile"))
    store = Enum.find(workflow["steps"], &(&1["stepName"] == "store"))

    assert length(extract["output"]["keywords"]) == 3
    assert is_binary(research["output"]["summary"])
    assert is_binary(compile["output"]["report"])
    assert store["output"]["stored"] == true
    assert store["output"]["reportLength"] > 0

    :ok =
      Assertions.assert_graph_shape(workflow_id, %{
        node_count: 4,
        edge_count: 3,
        edge_types: ["serial", "serial", "serial"]
      })
  end

  test "scenario 2 - serial + static parallel + merge + store", %{api_base: api_base} do
    {:ok, dev_base, dev_ref} = ScenarioTwoDeveloperServer.start(api_base: api_base)
    on_exit(fn -> ScenarioTwoDeveloperServer.stop(dev_ref) end)

    start_response = post_json!(dev_base <> "/start", %{"paragraph" => "alpha beta gamma"})
    workflow_id = start_response["workflowId"]
    on_exit(fn -> WorkflowStore.delete(workflow_id) end)

    workflow = Assertions.wait_for_completion(api_base, workflow_id, timeout_ms: 15_000)

    assert workflow["status"] == "completed"
    assert Enum.all?(workflow["steps"], &(&1["status"] == "completed"))
    assert Enum.find(workflow["steps"], &(&1["stepName"] == "store"))["output"]["stored"] == true

    :ok =
      Assertions.assert_graph_shape(workflow_id, %{
        node_count: 7,
        edge_types: [
          "fan_in",
          "fan_in",
          "fan_in",
          "fan_out",
          "fan_out",
          "fan_out",
          "serial",
          "serial",
          "serial",
          "serial",
          "serial",
          "serial",
          "serial"
        ]
      })
  end

  test "scenario 3 - serial + dynamic parallel + merge + store", %{api_base: api_base} do
    {:ok, dev_base, dev_ref} = ScenarioThreeDeveloperServer.start(api_base: api_base)
    on_exit(fn -> ScenarioThreeDeveloperServer.stop(dev_ref) end)

    start_response =
      post_json!(dev_base <> "/start", %{
        "paragraph" => "alpha beta gamma delta epsilon zeta eta"
      })

    workflow_id = start_response["workflowId"]
    on_exit(fn -> WorkflowStore.delete(workflow_id) end)

    workflow = Assertions.wait_for_completion(api_base, workflow_id, timeout_ms: 15_000)

    assert workflow["status"] == "completed"
    assert Enum.all?(workflow["steps"], &(&1["status"] == "completed"))
    assert Enum.find(workflow["steps"], &(&1["stepName"] == "store"))["output"]["stored"] == true

    research_steps = Enum.filter(workflow["steps"], &(&1["stepName"] == "research"))
    assert length(research_steps) == 5

    :ok = Assertions.assert_graph_shape(workflow_id, %{node_count: 9, edge_count: 21})
  end

  test "scenario 4 - dynamic parallel with per-branch summarize before final merge", %{
    api_base: api_base
  } do
    {:ok, dev_base, dev_ref} = ScenarioFourDeveloperServer.start(api_base: api_base)
    on_exit(fn -> ScenarioFourDeveloperServer.stop(dev_ref) end)

    start_response =
      post_json!(dev_base <> "/start", %{
        "paragraph" => "topicA topicB topicC topicD"
      })

    workflow_id = start_response["workflowId"]
    on_exit(fn -> WorkflowStore.delete(workflow_id) end)

    workflow = Assertions.wait_for_completion(api_base, workflow_id, timeout_ms: 15_000)

    assert workflow["status"] == "completed"
    assert Enum.all?(workflow["steps"], &(&1["status"] == "completed"))

    compile = Enum.find(workflow["steps"], &(&1["stepName"] == "compile"))
    store = Enum.find(workflow["steps"], &(&1["stepName"] == "store"))
    research_steps = Enum.filter(workflow["steps"], &(&1["stepName"] == "research"))
    summarise_steps = Enum.filter(workflow["steps"], &(&1["stepName"] == "summarise"))
    assert length(research_steps) == 3
    assert length(summarise_steps) == 3
    assert is_binary(compile["output"]["compiled"])
    assert store["output"]["stored"] == true

    :ok =
      Assertions.assert_graph_shape(workflow_id, %{
        node_count: 10,
        edge_count: 16
      })
  end

  test "scenario 5 - nested parallel fan-out with context-driven branch placement", %{
    api_base: api_base
  } do
    {:ok, dev_base, dev_ref} = ScenarioFiveDeveloperServer.start(api_base: api_base)
    on_exit(fn -> ScenarioFiveDeveloperServer.stop(dev_ref) end)

    start_response =
      post_json!(dev_base <> "/start", %{
        "paragraph" => "nested fanout research and search"
      })

    workflow_id = start_response["workflowId"]
    on_exit(fn -> WorkflowStore.delete(workflow_id) end)

    workflow = Assertions.wait_for_completion(api_base, workflow_id, timeout_ms: 20_000)

    assert workflow["status"] == "completed"
    assert Enum.all?(workflow["steps"], &(&1["status"] == "completed"))

    research_steps = Enum.filter(workflow["steps"], &(&1["stepName"] == "research"))
    search_steps = Enum.filter(workflow["steps"], &(&1["stepName"] == "search"))
    collect_steps = Enum.filter(workflow["steps"], &(&1["stepName"] == "collect"))
    summarise_steps = Enum.filter(workflow["steps"], &(&1["stepName"] == "summarise"))
    merge = Enum.find(workflow["steps"], &(&1["stepName"] == "merge_summaries"))
    store = Enum.find(workflow["steps"], &(&1["stepName"] == "store"))

    assert length(research_steps) == 2
    assert length(search_steps) == 4
    assert length(collect_steps) == 2
    assert length(summarise_steps) == 2
    assert is_binary(merge["output"]["compiled"])
    assert store["output"]["stored"] == true

    :ok =
      Assertions.assert_graph_shape(workflow_id, %{
        node_count: 16
      })
  end

  defp post_json!(url, payload) do
    case Req.post(url, json: payload) do
      {:ok, %{status: 201, body: body}} when is_map(body) ->
        body

      {:ok, %{status: status, body: body}} ->
        raise "POST #{url} expected 201, got #{status}: #{inspect(body)}"

      {:error, reason} ->
        raise "POST #{url} failed: #{inspect(reason)}"
    end
  end
end
