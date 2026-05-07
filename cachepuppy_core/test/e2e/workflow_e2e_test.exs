defmodule CachePuppyCore.E2E.WorkflowE2ETest do
  use ExUnit.Case, async: false

  alias CachePuppy.Test.E2E.{Assertions, CachePuppyHTTP, DeveloperServer}
  alias CachePuppyCore.Workflow.WorkflowStore

  setup_all do
    ref = {:cachepuppy_http_e2e, System.unique_integer([:positive, :monotonic])}

    {:ok, _pid} =
      Plug.Cowboy.http(CachePuppyCoreWeb.Endpoint, [], ref: ref, ip: {127, 0, 0, 1}, port: 0)

    api_base = "http://127.0.0.1:#{:ranch.get_port(ref)}"
    on_exit(fn -> Plug.Cowboy.shutdown(ref) end)
    {:ok, api_base: api_base}
  end

  test "scenario 1 serial workflow via real HTTP", %{api_base: api_base} do
    workflow = CachePuppyHTTP.create_workflow(api_base, "e2e-serial")
    workflow_id = workflow["workflowId"]
    {:ok, api_base_agent} = Agent.start_link(fn -> api_base end)
    {:ok, dev_base_agent} = Agent.start_link(fn -> nil end)
    {:ok, state_agent} = Agent.start_link(fn -> %{} end)

    {:ok, dev_base, dev_ref} =
      DeveloperServer.start(%{
        "extract" => fn input ->
          keywords = input["data"]["paragraph"] |> String.split(" ") |> Enum.take(3)

          CachePuppyHTTP.add_step(Agent.get(api_base_agent, & &1), workflow_id, %{
            "stepName" => "research",
            "url" => Agent.get(dev_base_agent, &(&1 <> "/step")),
            "method" => "post",
            "data" => %{"keywords" => keywords}
          })

          {200, %{"keywords" => keywords}}
        end,
        "research" => fn input ->
          summary = "summary: " <> Enum.join(input["data"]["keywords"], ", ")

          CachePuppyHTTP.add_step(Agent.get(api_base_agent, & &1), workflow_id, %{
            "stepName" => "compile",
            "url" => Agent.get(dev_base_agent, &(&1 <> "/step")),
            "method" => "post",
            "data" => %{"summary" => summary}
          })

          {200, %{"summary" => summary}}
        end,
        "compile" => fn input ->
          Agent.update(state_agent, &Map.put(&1, :compile_input, input))
          {200, %{"report" => "report: " <> input["data"]["summary"]}}
        end
      })

    Agent.update(dev_base_agent, fn _ -> dev_base end)

    on_exit(fn ->
      DeveloperServer.stop(dev_ref)
      WorkflowStore.delete(workflow_id)
    end)

    CachePuppyHTTP.add_step(api_base, workflow_id, %{
      "stepName" => "extract",
      "url" => dev_base <> "/step",
      "method" => "post",
      "data" => %{"paragraph" => "cachepuppy powers orchestration engines"}
    })

    state = Assertions.wait_for_completion(api_base, workflow_id)
    Assertions.assert_all_steps_completed(state)

    extract = Enum.find(state["steps"], &(&1["stepName"] == "extract"))
    research = Enum.find(state["steps"], &(&1["stepName"] == "research"))
    compile = Enum.find(state["steps"], &(&1["stepName"] == "compile"))

    assert length(extract["output"]["keywords"]) == 3
    assert is_binary(research["output"]["summary"])
    assert is_binary(compile["output"]["report"])

    assert Agent.get(state_agent, & &1.compile_input)["data"]["summary"] ==
             research["output"]["summary"]

    :ok =
      Assertions.assert_graph_shape(workflow_id, %{
        node_count: 3,
        edge_count: 2,
        edge_types: ["serial", "serial"]
      })
  end

  test "scenario 2 static parallel merge to serial via real HTTP", %{api_base: api_base} do
    workflow = CachePuppyHTTP.create_workflow(api_base, "e2e-static-parallel")
    workflow_id = workflow["workflowId"]
    {:ok, dev_base_agent} = Agent.start_link(fn -> nil end)
    {:ok, state_agent} = Agent.start_link(fn -> %{compile_count: 0} end)

    {:ok, dev_base, dev_ref} =
      DeveloperServer.start(%{
        "extract" => fn _ -> {200, %{"keywords" => ["alpha", "beta", "gamma"]}} end,
        "research_A" => fn input -> {200, %{"result" => "res:" <> input["data"]["keyword"]}} end,
        "research_B" => fn input -> {200, %{"result" => "res:" <> input["data"]["keyword"]}} end,
        "research_C" => fn input -> {200, %{"result" => "res:" <> input["data"]["keyword"]}} end,
        "compile" => fn input ->
          merge_data = Map.get(input, "mergeData", [])

          Agent.update(state_agent, fn s ->
            s
            |> Map.put(:merge_data, merge_data)
            |> Map.update!(:compile_count, &(&1 + 1))
          end)

          compiled = merge_data |> Enum.map(& &1["output"]["result"]) |> Enum.join(",")

          CachePuppyHTTP.add_step(api_base, workflow_id, %{
            "stepName" => "store",
            "url" => Agent.get(dev_base_agent, &(&1 <> "/step")),
            "method" => "post",
            "data" => %{"compiled" => compiled}
          })

          {200, %{"compiled" => compiled}}
        end,
        "store" => fn _ -> {200, %{"stored" => true}} end
      })

    Agent.update(dev_base_agent, fn _ -> dev_base end)

    on_exit(fn ->
      DeveloperServer.stop(dev_ref)
      WorkflowStore.delete(workflow_id)
    end)

    CachePuppyHTTP.add_step(api_base, workflow_id, %{
      "stepName" => "extract",
      "url" => dev_base <> "/step",
      "method" => "post",
      "data" => %{"paragraph" => "alpha beta gamma"}
    })

    CachePuppyHTTP.add_parallel(api_base, workflow_id, [
      %{
        "stepName" => "research_A",
        "url" => dev_base <> "/step",
        "method" => "post",
        "data" => %{"keyword" => "alpha"}
      },
      %{
        "stepName" => "research_B",
        "url" => dev_base <> "/step",
        "method" => "post",
        "data" => %{"keyword" => "beta"}
      },
      %{
        "stepName" => "research_C",
        "url" => dev_base <> "/step",
        "method" => "post",
        "data" => %{"keyword" => "gamma"}
      }
    ])

    CachePuppyHTTP.add_merge(api_base, workflow_id, %{
      "stepName" => "compile",
      "url" => dev_base <> "/step",
      "method" => "post",
      "data" => %{}
    })

    state = Assertions.wait_for_completion(api_base, workflow_id)
    Assertions.assert_all_steps_completed(state)

    assert Enum.find(state["steps"], &(&1["stepName"] == "store"))["output"]["stored"] == true
    assert length(Agent.get(state_agent, & &1.merge_data)) == 3
    assert Agent.get(state_agent, & &1.compile_count) == 1

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

  test "scenario 3 dynamic parallel n=5 via real HTTP", %{api_base: api_base} do
    workflow = CachePuppyHTTP.create_workflow(api_base, "e2e-dynamic")
    workflow_id = workflow["workflowId"]
    {:ok, dev_base_agent} = Agent.start_link(fn -> nil end)
    {:ok, state_agent} = Agent.start_link(fn -> %{branch_count: 0} end)

    {:ok, dev_base, dev_ref} =
      DeveloperServer.start(%{
        "extract" => fn input ->
          words = input["data"]["paragraph"] |> String.split(" ") |> Enum.take(5)

          CachePuppyHTTP.add_parallel(
            api_base,
            workflow_id,
            Enum.map(words, fn word ->
              %{
                "stepName" => "research",
                "url" => Agent.get(dev_base_agent, &(&1 <> "/step")),
                "method" => "post",
                "data" => %{"word" => word}
              }
            end)
          )

          CachePuppyHTTP.add_merge(api_base, workflow_id, %{
            "stepName" => "compile",
            "url" => Agent.get(dev_base_agent, &(&1 <> "/step")),
            "method" => "post",
            "data" => %{}
          })

          Agent.update(state_agent, &Map.put(&1, :branch_count, length(words)))
          {200, %{"n" => length(words)}}
        end,
        "research" => fn input ->
          word = input["data"]["word"]
          {200, %{"word" => word, "definition" => "definition of #{word}"}}
        end,
        "compile" => fn input ->
          merge_data = Map.get(input, "mergeData", [])

          CachePuppyHTTP.add_step(api_base, workflow_id, %{
            "stepName" => "store",
            "url" => Agent.get(dev_base_agent, &(&1 <> "/step")),
            "method" => "post",
            "data" => %{"definitions" => Enum.map(merge_data, & &1["output"])}
          })

          Agent.update(state_agent, &Map.put(&1, :merge_data, merge_data))
          {200, %{"definitions" => Enum.map(merge_data, & &1["output"])}}
        end,
        "store" => fn _ -> {200, %{"stored" => true}} end
      })

    Agent.update(dev_base_agent, fn _ -> dev_base end)

    on_exit(fn ->
      DeveloperServer.stop(dev_ref)
      WorkflowStore.delete(workflow_id)
    end)

    CachePuppyHTTP.add_step(api_base, workflow_id, %{
      "stepName" => "extract",
      "url" => dev_base <> "/step",
      "method" => "post",
      "data" => %{"paragraph" => "alpha beta gamma delta epsilon"}
    })

    state = Assertions.wait_for_completion(api_base, workflow_id)
    Assertions.assert_all_steps_completed(state)

    assert Agent.get(state_agent, & &1.branch_count) == 5
    assert length(Agent.get(state_agent, & &1.merge_data)) == 5
    assert Enum.find(state["steps"], &(&1["stepName"] == "store"))["output"]["stored"] == true

    :ok = Assertions.assert_graph_shape(workflow_id, %{node_count: 9, edge_count: 21})
  end

  test "scenario 4 dynamic parallel with nested-like branch processing via real HTTP", %{
    api_base: api_base
  } do
    workflow = CachePuppyHTTP.create_workflow(api_base, "e2e-nested")
    workflow_id = workflow["workflowId"]
    {:ok, dev_base_agent} = Agent.start_link(fn -> nil end)
    {:ok, state_agent} = Agent.start_link(fn -> %{compile_count: 0} end)

    {:ok, dev_base, dev_ref} =
      DeveloperServer.start(%{
        "extract" => fn input ->
          topics = input["data"]["paragraph"] |> String.split(" ") |> Enum.take(3)

          CachePuppyHTTP.add_parallel(
            api_base,
            workflow_id,
            Enum.map(topics, fn topic ->
              %{
                "stepName" => "research",
                "url" => Agent.get(dev_base_agent, &(&1 <> "/step")),
                "method" => "post",
                "data" => %{"topic" => topic}
              }
            end)
          )

          CachePuppyHTTP.add_merge(api_base, workflow_id, %{
            "stepName" => "compile",
            "url" => Agent.get(dev_base_agent, &(&1 <> "/step")),
            "method" => "post",
            "data" => %{}
          })

          {200, %{"topics" => topics}}
        end,
        "research" => fn input ->
          topic = input["data"]["topic"]
          {200, %{"topic" => topic, "summary" => "summary for #{topic}"}}
        end,
        "compile" => fn input ->
          Agent.update(state_agent, &Map.update!(&1, :compile_count, fn n -> n + 1 end))

          merged = Map.get(input, "mergeData", []) |> Enum.map(& &1["output"]["summary"])

          CachePuppyHTTP.add_step(api_base, workflow_id, %{
            "stepName" => "store",
            "url" => Agent.get(dev_base_agent, &(&1 <> "/step")),
            "method" => "post",
            "data" => %{"summaries" => merged}
          })

          {200, %{"compiled" => Enum.join(merged, " | ")}}
        end,
        "store" => fn _ -> {200, %{"stored" => true}} end
      })

    Agent.update(dev_base_agent, fn _ -> dev_base end)

    on_exit(fn ->
      DeveloperServer.stop(dev_ref)
      WorkflowStore.delete(workflow_id)
    end)

    CachePuppyHTTP.add_step(api_base, workflow_id, %{
      "stepName" => "extract",
      "url" => dev_base <> "/step",
      "method" => "post",
      "data" => %{"paragraph" => "topicA topicB topicC"}
    })

    state = Assertions.wait_for_completion(api_base, workflow_id)
    Assertions.assert_all_steps_completed(state)

    compile_step = Enum.find(state["steps"], &(&1["stepName"] == "compile"))
    assert is_binary(compile_step["output"]["compiled"])
    assert Agent.get(state_agent, & &1.compile_count) == 1
    assert Enum.find(state["steps"], &(&1["stepName"] == "store"))["output"]["stored"] == true

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
end
