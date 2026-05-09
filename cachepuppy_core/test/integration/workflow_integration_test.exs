defmodule CachePuppyCore.Integration.WorkflowIntegrationTest do
  use ExUnit.Case, async: false

  alias CachePuppy.Test.{StepServer, WorkflowHelpers}
  alias CachePuppyCore.Workflow.WorkflowStore
  alias CachePuppyCore.{WorkflowManager, WorkflowServer}

  test "scenario 1: serial workflow extract -> research -> compile" do
    workflow_id = unique_workflow_id("serial")
    {:ok, state_agent} = Agent.start_link(fn -> %{} end)
    {:ok, url_agent} = Agent.start_link(fn -> nil end)

    {:ok, base_url, server_ref} =
      StepServer.start(%{
        "extract" => fn input ->
          keywords = input["data"]["paragraph"] |> String.split(" ") |> Enum.take(3)

          {:ok, _} =
            WorkflowServer.add_step(workflow_id, %{
              step_id: "research",
              step_name: "research",
              url: Agent.get(url_agent, &(&1 <> "/step")),
              data: %{"keywords" => keywords}
            })

          {200, %{"keywords" => keywords}}
        end,
        "research" => fn input ->
          summary = "summary for " <> Enum.join(input["data"]["keywords"], ", ")

          {:ok, _} =
            WorkflowServer.add_step(workflow_id, %{
              step_id: "compile",
              step_name: "compile",
              url: Agent.get(url_agent, &(&1 <> "/step")),
              data: %{"summary" => summary}
            })

          {200, %{"summary" => summary}}
        end,
        "compile" => fn input ->
          report = "report: " <> input["data"]["summary"]
          Agent.update(state_agent, &Map.put(&1, :compile_input, input))
          {200, %{"report" => report}}
        end
      })

    Agent.update(url_agent, fn _ -> base_url end)

    on_exit(fn ->
      StepServer.stop(server_ref)
      WorkflowStore.delete(workflow_id)
    end)

    assert {:ok, _pid} = WorkflowManager.start_workflow(workflow_id, "scenario1")
    assert :ok = WorkflowHelpers.subscribe_to_workflow(workflow_id)

    assert {:ok, _extract} =
             WorkflowServer.add_step(workflow_id, %{
               step_id: "extract",
               step_name: "extract",
               url: base_url <> "/step",
               data: %{"paragraph" => "cachepuppy builds orchestration workflows reliably"}
             })

    workflow = WorkflowHelpers.wait_for_completion(workflow_id, timeout_ms: 12_000)
    broadcasts = WorkflowHelpers.collect_broadcasts(workflow_id)

    assert workflow.status == :completed
    assert Map.keys(workflow.steps) |> Enum.sort() == ["compile", "extract", "research"]
    assert Enum.all?(workflow.steps, fn {_id, step} -> step.status == :completed end)
    assert length(workflow.steps["extract"].output["keywords"]) == 3
    assert is_binary(workflow.steps["research"].output["summary"])
    assert String.length(workflow.steps["research"].output["summary"]) > 0
    assert is_binary(workflow.steps["compile"].output["report"])
    assert String.length(workflow.steps["compile"].output["report"]) > 0

    assert Agent.get(state_agent, & &1.compile_input)["data"]["summary"] ==
             workflow.steps["research"].output["summary"]

    :ok =
      WorkflowHelpers.assert_graph_shape(workflow_id, %{
        node_count: 3,
        edge_count: 2,
        edge_types: ["serial", "serial"]
      })

    assert_status_transitions(broadcasts, ["extract", "research", "compile"], [
      "running",
      "completed"
    ])
  end

  test "scenario 2: serial + static parallel + merge to serial" do
    workflow_id = unique_workflow_id("static-parallel")
    {:ok, state_agent} = Agent.start_link(fn -> %{merge_count: 0} end)
    {:ok, url_agent} = Agent.start_link(fn -> nil end)

    {:ok, base_url, server_ref} =
      StepServer.start(%{
        "extract" => fn _input ->
          {200, %{"keywords" => ["alpha", "beta", "gamma"]}}
        end,
        "research_A" => fn input ->
          {200, %{"result" => "researched " <> input["data"]["keyword"]}}
        end,
        "research_B" => fn input ->
          {200, %{"result" => "researched " <> input["data"]["keyword"]}}
        end,
        "research_C" => fn input ->
          {200, %{"result" => "researched " <> input["data"]["keyword"]}}
        end,
        "compile" => fn input ->
          merge_data = Map.get(input, "mergeData", [])

          Agent.update(state_agent, fn s ->
            s
            |> Map.put(:compile_merge_data, merge_data)
            |> Map.update!(:merge_count, &(&1 + 1))
          end)

          compiled =
            merge_data
            |> Enum.map(& &1["output"]["result"])
            |> Enum.join(", ")

          {:ok, _} =
            WorkflowServer.add_step(workflow_id, %{
              step_id: "store",
              step_name: "store",
              url: Agent.get(url_agent, &(&1 <> "/step")),
              data: %{"compiled" => compiled}
            })

          {200, %{"compiled" => compiled}}
        end,
        "store" => fn input ->
          Agent.update(state_agent, &Map.put(&1, :store_input, input))
          {200, %{"stored" => true}}
        end
      })

    Agent.update(url_agent, fn _ -> base_url end)

    on_exit(fn ->
      StepServer.stop(server_ref)
      WorkflowStore.delete(workflow_id)
    end)

    assert {:ok, _pid} = WorkflowManager.start_workflow(workflow_id, "scenario2")
    assert :ok = WorkflowHelpers.subscribe_to_workflow(workflow_id)

    assert {:ok, _extract} =
             WorkflowServer.add_step(workflow_id, %{
               step_id: "extract",
               step_name: "extract",
               url: base_url <> "/step",
               data: %{"paragraph" => "alpha beta gamma"}
             })

    assert {:ok, _gid, _branches, _merge} =
             WorkflowServer.add_parallel(
               workflow_id,
               [
                 step("ra", "research_A", base_url, %{"keyword" => "alpha"}),
                 step("rb", "research_B", base_url, %{"keyword" => "beta"}),
                 step("rc", "research_C", base_url, %{"keyword" => "gamma"})
               ],
               %{
                 step_id: "compile",
                 step_name: "compile",
                 url: base_url <> "/step"
               }
             )

    assert {:ok, _} = WorkflowServer.merge_now(workflow_id, "compile")

    workflow = WorkflowHelpers.wait_for_completion(workflow_id, timeout_ms: 12_000)
    broadcasts = WorkflowHelpers.collect_broadcasts(workflow_id)

    assert workflow.status == :completed
    assert Enum.all?(workflow.steps, fn {_id, st} -> st.status == :completed end)
    assert workflow.steps["store"].output["stored"] == true

    parallel_completed =
      workflow.steps
      |> Map.values()
      |> Enum.filter(&(&1.group_type == :parallel_branch and &1.status == :completed))
      |> length()

    assert parallel_completed == 3
    assert length(Agent.get(state_agent, & &1.compile_merge_data)) == 3
    assert Agent.get(state_agent, & &1.store_input)["data"]["compiled"] != nil

    :ok =
      WorkflowHelpers.assert_graph_shape(workflow_id, %{
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

    assert_status_transitions(broadcasts, ["extract", "ra", "rb", "rc", "compile", "store"], [
      "running",
      "completed"
    ])
  end

  test "scenario 3: serial + dynamic parallel + merge to serial (N=5)" do
    workflow_id = unique_workflow_id("dynamic-parallel")
    {:ok, state_agent} = Agent.start_link(fn -> %{merge_count: 0, dynamic_count: 0} end)
    {:ok, url_agent} = Agent.start_link(fn -> nil end)

    {:ok, base_url, server_ref} =
      StepServer.start(%{
        "extract" => fn input ->
          words = input["data"]["paragraph"] |> String.split(" ") |> Enum.take(5)

          steps =
            words
            |> Enum.with_index(1)
            |> Enum.map(fn {word, idx} ->
              step("research_#{idx}", "research", Agent.get(url_agent, & &1), %{"word" => word})
            end)

          {:ok, _gid, _branches, _merge} =
            WorkflowServer.add_parallel(workflow_id, steps, %{
              step_id: "compile",
              step_name: "compile",
              url: Agent.get(url_agent, &(&1 <> "/step"))
            })

          {:ok, _} = WorkflowServer.merge_now(workflow_id, "compile")

          Agent.update(state_agent, &Map.put(&1, :dynamic_count, length(steps)))
          {200, %{"generated" => length(steps)}}
        end,
        "research" => fn input ->
          word = input["data"]["word"]
          {200, %{"word" => word, "definition" => "definition of #{word}"}}
        end,
        "compile" => fn input ->
          merge_data = Map.get(input, "mergeData", [])

          definitions =
            merge_data
            |> Enum.map(fn item ->
              %{"word" => item["output"]["word"], "definition" => item["output"]["definition"]}
            end)

          Agent.update(state_agent, fn s ->
            s
            |> Map.put(:compile_merge_data, merge_data)
            |> Map.update!(:merge_count, &(&1 + 1))
          end)

          {:ok, _} =
            WorkflowServer.add_step(workflow_id, %{
              step_id: "store",
              step_name: "store",
              url: Agent.get(url_agent, &(&1 <> "/step")),
              data: %{"definitions" => definitions}
            })

          {200, %{"definitions" => definitions}}
        end,
        "store" => fn _input ->
          {200, %{"stored" => true}}
        end
      })

    Agent.update(url_agent, fn _ -> base_url end)

    on_exit(fn ->
      StepServer.stop(server_ref)
      WorkflowStore.delete(workflow_id)
    end)

    assert {:ok, _pid} = WorkflowManager.start_workflow(workflow_id, "scenario3")
    assert :ok = WorkflowHelpers.subscribe_to_workflow(workflow_id)

    assert {:ok, _extract} =
             WorkflowServer.add_step(workflow_id, %{
               step_id: "extract",
               step_name: "extract",
               url: base_url <> "/step",
               data: %{"paragraph" => "alpha beta gamma delta epsilon"}
             })

    workflow = WorkflowHelpers.wait_for_completion(workflow_id, timeout_ms: 12_000)

    assert workflow.status == :completed
    assert Enum.all?(workflow.steps, fn {_id, st} -> st.status == :completed end)
    assert Agent.get(state_agent, & &1.dynamic_count) == 5

    dynamic_steps =
      workflow.steps
      |> Map.values()
      |> Enum.filter(&String.starts_with?(&1.step_id, "research_"))

    assert length(dynamic_steps) == 5
    assert Enum.all?(dynamic_steps, &(&1.status == :completed))

    merge_data = Agent.get(state_agent, & &1.compile_merge_data)
    assert length(merge_data) == 5

    assert Enum.all?(
             merge_data,
             &(is_binary(&1["output"]["word"]) and is_binary(&1["output"]["definition"]))
           )

    :ok =
      WorkflowHelpers.assert_graph_shape(workflow_id, %{
        node_count: 9,
        edge_count: 21
      })
  end

  test "scenario 4: dynamic parallel with nested serial branches and merge" do
    workflow_id = unique_workflow_id("nested-parallel")
    {:ok, state_agent} = Agent.start_link(fn -> %{compile_count: 0} end)
    {:ok, url_agent} = Agent.start_link(fn -> nil end)

    {:ok, base_url, server_ref} =
      StepServer.start(%{
        "extract" => fn input ->
          topics = input["data"]["paragraph"] |> String.split(" ") |> Enum.take(3)

          research_steps =
            topics
            |> Enum.with_index(1)
            |> Enum.map(fn {topic, idx} ->
              step(
                "research_#{idx}",
                "research",
                Agent.get(url_agent, & &1),
                %{"topic" => topic},
                ["extract"]
              )
            end)

          Enum.each(research_steps, fn s ->
            {:ok, _} = WorkflowServer.add_step(workflow_id, s)
          end)

          summarise_steps =
            topics
            |> Enum.with_index(1)
            |> Enum.map(fn {topic, idx} ->
              step(
                "summarise_#{idx}",
                "summarise",
                Agent.get(url_agent, & &1),
                %{"topic" => topic, "researchStepId" => "research_#{idx}"},
                [
                  "research_#{idx}"
                ]
              )
            end)

          {:ok, _gid, _branches, _merge} =
            WorkflowServer.add_parallel(workflow_id, summarise_steps, %{
              step_id: "compile",
              step_name: "compile",
              url: Agent.get(url_agent, &(&1 <> "/step"))
            })

          {:ok, _} = WorkflowServer.merge_now(workflow_id, "compile")

          {200, %{"topics" => topics}}
        end,
        "research" => fn input ->
          topic = input["data"]["topic"]
          {200, %{"topic" => topic, "notes" => "facts about #{topic}"}}
        end,
        "summarise" => fn input ->
          rid = input["data"]["researchStepId"]
          {:ok, wf} = WorkflowServer.get_state(workflow_id)
          research_output = wf.steps[rid].output
          {200, %{"summary" => "summary: #{research_output["notes"]}"}}
        end,
        "compile" => fn input ->
          merge_data = Map.get(input, "mergeData", [])
          Agent.update(state_agent, &Map.update!(&1, :compile_count, fn n -> n + 1 end))

          compiled =
            merge_data
            |> Enum.map(& &1["output"]["summary"])
            |> Enum.join(" | ")

          {:ok, _} =
            WorkflowServer.add_step(workflow_id, %{
              step_id: "store",
              step_name: "store",
              url: Agent.get(url_agent, &(&1 <> "/step")),
              data: %{"compiled" => compiled}
            })

          {200, %{"compiled" => compiled}}
        end,
        "store" => fn _input ->
          {200, %{"stored" => true}}
        end
      })

    Agent.update(url_agent, fn _ -> base_url end)

    on_exit(fn ->
      StepServer.stop(server_ref)
      WorkflowStore.delete(workflow_id)
    end)

    assert {:ok, _pid} = WorkflowManager.start_workflow(workflow_id, "scenario4")
    assert :ok = WorkflowHelpers.subscribe_to_workflow(workflow_id)

    assert {:ok, _extract} =
             WorkflowServer.add_step(workflow_id, %{
               step_id: "extract",
               step_name: "extract",
               url: base_url <> "/step",
               data: %{"paragraph" => "topicA topicB topicC"}
             })

    workflow = WorkflowHelpers.wait_for_completion(workflow_id, timeout_ms: 15_000)
    broadcasts = WorkflowHelpers.collect_broadcasts(workflow_id)

    research_steps =
      workflow.steps |> Map.values() |> Enum.filter(&String.starts_with?(&1.step_id, "research_"))

    summarise_steps =
      workflow.steps
      |> Map.values()
      |> Enum.filter(&String.starts_with?(&1.step_id, "summarise_"))

    assert workflow.status == :completed
    assert length(research_steps) == 3
    assert length(summarise_steps) == 3
    assert Enum.all?(research_steps, &(&1.status == :completed))
    assert Enum.all?(summarise_steps, &(&1.status == :completed))
    assert Agent.get(state_agent, & &1.compile_count) == 1

    :ok =
      WorkflowHelpers.assert_graph_shape(workflow_id, %{
        node_count: 10,
        edge_count: 22
      })

    assert Enum.all?(1..3, fn idx ->
             Enum.any?(workflow.steps["summarise_#{idx}"].parent_ids, &(&1 == "research_#{idx}"))
           end)

    assert Enum.all?(1..3, fn idx ->
             branch_id = "summarise_#{idx}"
             Enum.any?(workflow.steps["compile"].parent_ids, &(&1 == branch_id))
           end)

    assert_status_transitions(
      broadcasts,
      [
        "extract",
        "research_1",
        "research_2",
        "research_3",
        "summarise_1",
        "summarise_2",
        "summarise_3",
        "compile",
        "store"
      ],
      ["running", "completed"]
    )
  end

  test "context-driven nested parallel without explicit parent_ids" do
    workflow_id = unique_workflow_id("context-nested")
    {:ok, state_agent} = Agent.start_link(fn -> %{final_merge_count: 0} end)
    {:ok, url_agent} = Agent.start_link(fn -> nil end)

    {:ok, base_url, server_ref} =
      StepServer.start(%{
        "extract" => fn _input ->
          steps = [
            step("research_a", "research", Agent.get(url_agent, & &1), %{"topic" => "A"}),
            step("research_b", "research", Agent.get(url_agent, & &1), %{"topic" => "B"})
          ]

          {:ok, _gid, _branches, _merge} =
            WorkflowServer.add_parallel(workflow_id, steps, %{
              step_id: "final_merge",
              step_name: "final_merge",
              url: Agent.get(url_agent, &(&1 <> "/step"))
            })

          {:ok, _} = WorkflowServer.merge_now(workflow_id, "final_merge")
          {200, %{"ok" => true}}
        end,
        "research" => fn input ->
          step_id = input["stepId"]

          {:ok, _gid, _branches, _merge} =
            WorkflowServer.add_parallel(
              workflow_id,
              [
                step("#{step_id}_s1", "search", Agent.get(url_agent, & &1), %{
                  "q" => "#{step_id}-1"
                }),
                step("#{step_id}_s2", "search", Agent.get(url_agent, & &1), %{
                  "q" => "#{step_id}-2"
                })
              ],
              %{
                step_id: "#{step_id}_collect",
                step_name: "collect",
                url: Agent.get(url_agent, &(&1 <> "/step"))
              },
              invoking_step_id: step_id
            )

          {:ok, _} = WorkflowServer.merge_now(workflow_id, "#{step_id}_collect")
          {200, %{"branch" => step_id}}
        end,
        "search" => fn input ->
          {200, %{"result" => "hit:" <> input["data"]["q"]}}
        end,
        "collect" => fn input ->
          step_id = input["stepId"]
          topic_id = String.replace_suffix(step_id, "_collect", "")

          {:ok, _} =
            WorkflowServer.add_step(
              workflow_id,
              %{
                step_id: "#{topic_id}_summary",
                step_name: "summarise",
                url: Agent.get(url_agent, &(&1 <> "/step")),
                data: %{"topic" => topic_id}
              },
              invoking_step_id: step_id
            )

          {200, %{"collected" => length(Map.get(input, "mergeData", []))}}
        end,
        "summarise" => fn input ->
          {200, %{"summary" => "summary:" <> input["data"]["topic"]}}
        end,
        "final_merge" => fn input ->
          merge_data = Map.get(input, "mergeData", [])
          Agent.update(state_agent, &Map.update!(&1, :final_merge_count, fn n -> n + 1 end))
          {200, %{"merged" => Enum.map(merge_data, & &1["output"]["summary"])}}
        end
      })

    Agent.update(url_agent, fn _ -> base_url end)

    on_exit(fn ->
      StepServer.stop(server_ref)
      WorkflowStore.delete(workflow_id)
    end)

    assert {:ok, _pid} = WorkflowManager.start_workflow(workflow_id, "context_nested")
    assert :ok = WorkflowHelpers.subscribe_to_workflow(workflow_id)

    assert {:ok, _extract} =
             WorkflowServer.add_step(workflow_id, %{
               step_id: "extract",
               step_name: "extract",
               url: base_url <> "/step",
               data: %{}
             })

    workflow = WorkflowHelpers.wait_for_completion(workflow_id, timeout_ms: 20_000)

    assert workflow.status == :completed
    assert Agent.get(state_agent, & &1.final_merge_count) == 1
    assert workflow.steps["research_a_summary"].status == :completed
    assert workflow.steps["research_b_summary"].status == :completed

    assert Enum.sort(workflow.steps["final_merge"].parent_ids) == [
             "research_a_summary",
             "research_b_summary"
           ]

    assert workflow.groups
           |> Map.values()
           |> Enum.count(&match?(%CachePuppyCore.Workflow.ParallelGroup{}, &1)) == 3
  end

  test "failed parallel branch can be retried after process reconstruction" do
    workflow_id = unique_workflow_id("retry-reconstruct")
    {:ok, state_agent} = Agent.start_link(fn -> %{p1_attempts: 0, p2_runs: 0} end)
    {:ok, url_agent} = Agent.start_link(fn -> nil end)

    {:ok, base_url, server_ref} =
      StepServer.start(%{
        "extract" => fn _input ->
          {:ok, _gid, _branches, _merge} =
            WorkflowServer.add_parallel(
              workflow_id,
              [
                %{
                  step_id: "p1",
                  step_name: "p1",
                  url: Agent.get(url_agent, &(&1 <> "/step")),
                  data: %{},
                  max_retries: 0
                },
                %{
                  step_id: "p2",
                  step_name: "p2",
                  url: Agent.get(url_agent, &(&1 <> "/step")),
                  data: %{},
                  max_retries: 0
                }
              ],
              %{
                step_id: "compile",
                step_name: "compile",
                url: Agent.get(url_agent, &(&1 <> "/step"))
              }
            )

          {:ok, _} = WorkflowServer.merge_now(workflow_id, "compile")
          {200, %{"ok" => true}}
        end,
        "p1" => fn _input ->
          attempt =
            Agent.get_and_update(state_agent, fn s ->
              {s.p1_attempts + 1, %{s | p1_attempts: s.p1_attempts + 1}}
            end)

          if attempt <= 4 do
            {500, %{"error" => "p1_failed_once"}}
          else
            {200, %{"p1" => "ok"}}
          end
        end,
        "p2" => fn _input ->
          Agent.update(state_agent, &Map.update!(&1, :p2_runs, fn n -> n + 1 end))
          {200, %{"p2" => "ok"}}
        end,
        "compile" => fn input ->
          merge_data = Map.get(input, "mergeData", [])
          merged = merge_data |> Enum.map(& &1["step_id"]) |> Enum.sort()

          {:ok, _} =
            WorkflowServer.add_step(workflow_id, %{
              step_id: "store",
              step_name: "store",
              url: Agent.get(url_agent, &(&1 <> "/step")),
              data: %{"merged" => merged}
            })

          {200, %{"merged" => merged}}
        end,
        "store" => fn _input ->
          {200, %{"stored" => true}}
        end
      })

    Agent.update(url_agent, fn _ -> base_url end)

    on_exit(fn ->
      StepServer.stop(server_ref)
      WorkflowStore.delete(workflow_id)
    end)

    assert {:ok, pid} = WorkflowManager.start_workflow(workflow_id, "retry_reconstruct")
    assert :ok = WorkflowHelpers.subscribe_to_workflow(workflow_id)

    assert {:ok, _extract} =
             WorkflowServer.add_step(workflow_id, %{
               step_id: "extract",
               step_name: "extract",
               url: base_url <> "/step",
               data: %{}
             })

    wait_for(
      fn ->
        assert {:ok, wf} = WorkflowServer.get_state(workflow_id)
        assert wf.status == :failed
        assert wf.steps["p1"].status == :failed
        assert wf.steps["p2"].status == :completed
      end,
      500
    )

    ref = Process.monitor(pid)
    assert :ok = Horde.DynamicSupervisor.terminate_child(CachePuppyCore.WorkflowSupervisor, pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}

    assert {:ok, _pid2} = WorkflowManager.lookup(workflow_id)
    assert {:ok, _} = WorkflowServer.retry_step(workflow_id, "p1")

    workflow = WorkflowHelpers.wait_for_completion(workflow_id, timeout_ms: 15_000)
    assert workflow.status == :completed
    assert workflow.steps["p1"].status == :completed
    assert workflow.steps["p2"].status == :completed
    assert workflow.steps["store"].status == :completed
    assert Agent.get(state_agent, & &1.p2_runs) == 1
  end

  defp unique_workflow_id(prefix) do
    "#{prefix}-#{Base.encode16(:crypto.strong_rand_bytes(5), case: :lower)}"
  end

  defp wait_for(assertion_fun, attempts)
  defp wait_for(assertion_fun, 0), do: assertion_fun.()

  defp wait_for(assertion_fun, attempts) do
    try do
      assertion_fun.()
    rescue
      ExUnit.AssertionError ->
        Process.sleep(20)
        wait_for(assertion_fun, attempts - 1)
    end
  end

  defp step(step_id, step_name, base_url, data, parent_ids \\ []) do
    %{
      step_id: step_id,
      step_name: step_name,
      url: base_url <> "/step",
      data: data,
      parent_ids: parent_ids
    }
  end

  defp assert_status_transitions(diffs, step_ids, required_statuses) do
    status_by_node =
      Enum.reduce(diffs, %{}, fn diff, acc ->
        nodes = Map.get(diff, "addedNodes", []) ++ Map.get(diff, "changedNodes", [])

        Enum.reduce(nodes, acc, fn node, acc2 ->
          node_id = node["nodeId"]
          status = node["status"]

          if is_binary(node_id) and is_binary(status) do
            Map.update(acc2, node_id, MapSet.new([status]), &MapSet.put(&1, status))
          else
            acc2
          end
        end)
      end)

    Enum.each(step_ids, fn step_id ->
      statuses = Map.get(status_by_node, step_id, MapSet.new())

      Enum.each(required_statuses, fn expected ->
        assert MapSet.member?(statuses, expected),
               "expected #{step_id} broadcasts to include status #{expected}, got #{inspect(MapSet.to_list(statuses))}"
      end)
    end)
  end
end
