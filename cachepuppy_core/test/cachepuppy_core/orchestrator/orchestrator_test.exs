defmodule CachePuppyCore.OrchestratorTest do
  use ExUnit.Case, async: true

  alias CachePuppyCore.Orchestrator
  alias CachePuppyCore.Workflow
  alias CachePuppyCore.Workflow.Step

  test "advance schedules runnable step and keeps pending blocked by parents" do
    s1 = %Step{step_id: "s1", step_name: "a", url: "http://a", status: :pending}

    s2 = %Step{
      step_id: "s2",
      step_name: "b",
      url: "http://b",
      status: :pending,
      parent_ids: ["s1"]
    }

    wf = %Workflow{id: "wf-1", status: :running, steps: %{"s1" => s1, "s2" => s2}}

    {_wf, actions} = Orchestrator.advance(wf)
    assert [{:execute_step, %Step{step_id: "s1"}, _}] = actions
  end

  test "on_step_result marks workflow failed on executor error" do
    s1 = %Step{step_id: "s1", step_name: "a", url: "http://a", status: :running}

    wf = %Workflow{
      id: "wf-1",
      status: :running,
      steps: %{"s1" => s1},
      active_step_ids: MapSet.new(["s1"])
    }

    {wf, actions} = Orchestrator.on_step_result(wf, "s1", {:error, %{reason: :timeout}})
    assert actions == []
    assert wf.status == :failed
    assert wf.steps["s1"].status == :failed
  end
end
