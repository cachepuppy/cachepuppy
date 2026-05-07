defmodule CachePuppyCore.Graph.BroadcasterTest do
  use ExUnit.Case, async: false

  alias CachePuppyCore.Graph.Broadcaster
  alias CachePuppyCore.Workflow
  alias CachePuppyCore.Workflow.{Step, WorkflowStore}

  test "broadcast publishes non-empty diff and persists graph snapshot" do
    workflow_id = "wf-bc-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    topic = "workflow:" <> workflow_id

    step = %Step{step_id: "s1", step_name: "extract", url: "http://x", status: :pending}
    wf = %Workflow{id: workflow_id, name: "wf", status: :running, steps: %{"s1" => step}}
    :ok = WorkflowStore.put(workflow_id, wf)

    :ok = Phoenix.PubSub.subscribe(CachePuppyCore.PubSub, topic)
    :ok = Broadcaster.broadcast(workflow_id)

    assert_receive {:graph_diff, diff}
    assert diff["workflowId"] == workflow_id

    assert {:ok, updated} = WorkflowStore.get(workflow_id)
    assert updated.graph_snapshot != nil

    WorkflowStore.delete(workflow_id)
  end

  test "broadcast no-op when diff is empty" do
    workflow_id = "wf-bc-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    topic = "workflow:" <> workflow_id

    step = %Step{step_id: "s1", step_name: "extract", url: "http://x", status: :pending}
    wf = %Workflow{id: workflow_id, status: :running, steps: %{"s1" => step}}
    :ok = WorkflowStore.put(workflow_id, wf)

    :ok = Broadcaster.broadcast(workflow_id)
    assert {:ok, wf2} = WorkflowStore.get(workflow_id)
    assert wf2.graph_snapshot != nil

    :ok = Phoenix.PubSub.subscribe(CachePuppyCore.PubSub, topic)
    :ok = Broadcaster.broadcast(workflow_id)

    refute_receive {:graph_diff, _}
    WorkflowStore.delete(workflow_id)
  end
end
