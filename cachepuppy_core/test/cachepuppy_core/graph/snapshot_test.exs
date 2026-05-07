defmodule CachePuppyCore.Graph.SnapshotTest do
  use ExUnit.Case, async: true

  alias CachePuppyCore.Graph
  alias CachePuppyCore.Graph.Snapshot
  alias CachePuppyCore.Workflow

  test "put/get graph snapshot on workflow struct" do
    wf = %Workflow{id: "wf", status: :running}
    g = %Graph{workflow_id: "wf", status: "running", nodes: [], edges: [], updated_at: "x"}

    wf = Snapshot.put(wf, g)
    assert Snapshot.get(wf) == g
  end
end
