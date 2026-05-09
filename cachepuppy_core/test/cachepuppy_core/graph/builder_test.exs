defmodule CachePuppyCore.Graph.BuilderTest do
  use ExUnit.Case, async: true

  alias CachePuppyCore.Graph.Builder
  alias CachePuppyCore.Workflow
  alias CachePuppyCore.Workflow.{ParallelGroup, Step}

  test "builds serial graph with parent edge" do
    s1 = %Step{step_id: "a", step_name: "extract", url: "http://x", status: :completed}
    s2 = %Step{step_id: "b", step_name: "refine", url: "http://x", parent_ids: ["a"]}

    wf = %Workflow{id: "wf1", name: "n", status: :running, steps: %{"a" => s1, "b" => s2}}
    g = Builder.build(wf)

    assert g.workflow_id == "wf1"
    assert Enum.any?(g.nodes, &(&1["nodeId"] == "a"))
    assert Enum.any?(g.edges, &(&1["from"] == "a" and &1["to"] == "b" and &1["type"] == "serial"))
  end

  test "builds parallel fan_out and fan_in edges" do
    p1 = %Step{
      step_id: "p1",
      step_name: "p1",
      url: "http://x",
      parent_ids: ["root"],
      group_id: "g1",
      group_type: :parallel_branch
    }

    p2 = %Step{
      step_id: "p2",
      step_name: "p2",
      url: "http://x",
      parent_ids: ["root"],
      group_id: "g1",
      group_type: :parallel_branch
    }

    merge = %Step{
      step_id: "m1",
      step_name: "merge",
      url: "http://x",
      parent_ids: ["p1", "p2"],
      group_id: "g1",
      group_type: :parallel_merge
    }

    root = %Step{step_id: "root", step_name: "root", url: "http://x"}

    pg = %ParallelGroup{
      group_id: "g1",
      total_branches: 2,
      completed_branches: 1,
      merge_step_id: "m1",
      branch_root_step_ids: ["p1", "p2"],
      branch_terminal_step_ids: %{"p1" => "p1", "p2" => "p2"},
      status: :open
    }

    wf = %Workflow{
      id: "wf2",
      status: :running,
      steps: %{"root" => root, "p1" => p1, "p2" => p2, "m1" => merge},
      groups: %{"g1" => pg}
    }

    g = Builder.build(wf)

    assert Enum.any?(g.nodes, &(&1["nodeId"] == "g1" and &1["type"] == "parallel_group"))

    assert Enum.any?(
             g.edges,
             &(&1["from"] == "root" and &1["to"] == "p1" and &1["type"] == "fan_out")
           )

    assert Enum.any?(
             g.edges,
             &(&1["from"] == "p2" and &1["to"] == "m1" and &1["type"] == "fan_in")
           )
  end

end
