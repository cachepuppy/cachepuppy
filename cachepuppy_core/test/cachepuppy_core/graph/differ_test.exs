defmodule CachePuppyCore.Graph.DifferTest do
  use ExUnit.Case, async: true

  alias CachePuppyCore.Graph
  alias CachePuppyCore.Graph.Differ

  test "nil previous graph treats all as added" do
    current = %Graph{
      workflow_id: "wf",
      status: "running",
      nodes: [%{"nodeId" => "a", "status" => "pending"}],
      edges: [%{"from" => "a", "to" => "b", "type" => "serial"}],
      updated_at: "2026-01-01T00:00:00Z"
    }

    diff = Differ.diff(nil, current)
    assert length(diff["addedNodes"]) == 1
    assert length(diff["addedEdges"]) == 1
    assert diff["changedNodes"] == []
  end

  test "detects changed node fields and added edges" do
    prev = %Graph{
      workflow_id: "wf",
      status: "running",
      nodes: [
        %{
          "nodeId" => "a",
          "status" => "pending",
          "output" => nil,
          "error" => nil,
          "retryCount" => 0,
          "startedAt" => nil,
          "completedAt" => nil
        }
      ],
      edges: [],
      updated_at: "t1"
    }

    curr = %Graph{
      workflow_id: "wf",
      status: "running",
      nodes: [
        %{
          "nodeId" => "a",
          "status" => "completed",
          "output" => %{"ok" => true},
          "error" => nil,
          "retryCount" => 1,
          "startedAt" => "s",
          "completedAt" => "c"
        }
      ],
      edges: [%{"from" => "a", "to" => "b", "type" => "serial"}],
      updated_at: "t2"
    }

    diff = Differ.diff(prev, curr)
    assert length(diff["changedNodes"]) == 1
    assert length(diff["addedEdges"]) == 1
    refute Differ.empty_diff?(diff)
  end

  test "empty_diff? true when nothing changed" do
    g = %Graph{workflow_id: "wf", status: "running", nodes: [], edges: [], updated_at: "x"}
    diff = Differ.diff(g, g)
    assert Differ.empty_diff?(diff)
  end
end
