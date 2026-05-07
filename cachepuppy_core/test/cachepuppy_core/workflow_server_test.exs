defmodule CachePuppyCore.WorkflowServerTest do
  use ExUnit.Case, async: false

  alias CachePuppyCore.Workflow.ParallelGroup
  alias CachePuppyCore.Workflow.WorkflowStore
  alias CachePuppyCore.{WorkflowManager, WorkflowServer}

  setup do
    wid = "wf-test-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    on_exit(fn -> WorkflowStore.delete(wid) end)
    {:ok, workflow_id: wid}
  end

  test "get_state on fresh workflow is pending with empty steps", %{workflow_id: wid} do
    assert {:ok, _pid} = WorkflowManager.ensure_started(wid)
    assert {:ok, wf} = WorkflowServer.get_state(wid)
    assert wf.id == wid
    assert wf.status == :pending
    assert wf.steps == %{}
  end

  test "add_step activates workflow and chains serial tail", %{workflow_id: wid} do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)

    s1 = %{step_id: "a", step_name: "one", url: "http://example/a"}
    assert {:ok, _} = WorkflowServer.add_step(wid, s1)

    assert {:ok, wf} = WorkflowServer.get_state(wid)
    assert wf.status == :running
    assert wf.serial_tail_step_id == "a"
    assert wf.steps["a"].parent_ids == []

    s2 = %{step_id: "b", step_name: "two", url: "http://example/b"}
    assert {:ok, _} = WorkflowServer.add_step(wid, s2)

    assert {:ok, wf} = WorkflowServer.get_state(wid)
    assert wf.steps["b"].parent_ids == ["a"]
    assert wf.serial_tail_step_id == "b"
  end

  test "add_merge_step returns error when no open parallel group", %{workflow_id: wid} do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)

    merge = %{step_id: "m", step_name: "merge", url: "http://example/m"}
    assert {:error, :no_open_parallel_group} = WorkflowServer.add_merge_step(wid, merge)
  end

  test "parallel resume increments completed_branches and collects outputs", %{workflow_id: wid} do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)

    branches = [
      %{step_id: "p1", step_name: "b1", url: "http://example/p1"},
      %{step_id: "p2", step_name: "b2", url: "http://example/p2"}
    ]

    assert {:ok, gid, _} = WorkflowServer.add_parallel_steps(wid, branches)

    assert {:ok, wf} = WorkflowServer.get_state(wid)
    assert %ParallelGroup{completed_branches: 0, collected_outputs: []} = wf.groups[gid]

    out1 = %{"x" => 1}
    assert {:ok, _} = WorkflowServer.resume(wid, "p1", out1)

    assert {:ok, wf} = WorkflowServer.get_state(wid)
    pg = wf.groups[gid]
    assert pg.completed_branches == 1
    assert pg.collected_outputs == [%{step_id: "p1", output: out1}]

    out2 = %{"x" => 2}
    assert {:ok, _} = WorkflowServer.resume(wid, "p2", out2)

    assert {:ok, wf} = WorkflowServer.get_state(wid)
    pg = wf.groups[gid]
    assert pg.completed_branches == 2

    assert pg.collected_outputs == [
             %{step_id: "p1", output: out1},
             %{step_id: "p2", output: out2}
           ]
  end

  test "reloads workflow from ETS after supervisor terminates child", %{workflow_id: wid} do
    assert {:ok, pid} = WorkflowManager.ensure_started(wid)

    assert {:ok, _} =
             WorkflowServer.add_step(wid, %{
               step_id: "persisted",
               step_name: "n",
               url: "http://example/n"
             })

    ref = Process.monitor(pid)
    assert :ok = Horde.DynamicSupervisor.terminate_child(CachePuppyCore.WorkflowSupervisor, pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}

    assert {:ok, pid2} = WorkflowManager.ensure_started(wid)
    assert pid2 != pid

    assert {:ok, wf} = WorkflowServer.get_state(wid)
    assert Map.has_key?(wf.steps, "persisted")
    assert wf.steps["persisted"].step_name == "n"
  end

  test "end_workflow rejects when already completed", %{workflow_id: wid} do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)
    assert :ok = WorkflowServer.end_workflow(wid)
    assert {:error, :invalid_status} = WorkflowServer.end_workflow(wid)
  end

  test "mutations rejected after workflow completed", %{workflow_id: wid} do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)
    assert :ok = WorkflowServer.end_workflow(wid)

    step = %{step_id: "late", step_name: "late", url: "http://example/late"}
    assert {:error, :invalid_status} = WorkflowServer.add_step(wid, step)
  end

  test "add_merge_step attaches merge and closes open parallel group", %{workflow_id: wid} do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)

    assert {:ok, gid, _} =
             WorkflowServer.add_parallel_steps(wid, [
               %{step_id: "b1", step_name: "b1", url: "http://example/b1"}
             ])

    merge = %{step_id: "m", step_name: "merge", url: "http://example/m"}
    assert {:ok, mstep} = WorkflowServer.add_merge_step(wid, merge)
    assert mstep.parent_ids == ["b1"]

    assert {:ok, wf} = WorkflowServer.get_state(wid)
    assert wf.open_parallel_group_id == nil
    assert wf.serial_tail_step_id == "m"
    assert wf.groups[gid].merge_step_id == "m"
    assert wf.groups[gid].status == :waiting_for_merge_step
  end

  test "add_loop creates loop group and step", %{workflow_id: wid} do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)

    step = %{step_id: "loop1", step_name: "refine", url: "http://example/r"}
    assert {:ok, gid} = WorkflowServer.add_loop(wid, step, "result.score < 0.8", 5)

    assert {:ok, wf} = WorkflowServer.get_state(wid)
    assert wf.groups[gid].step_name == "refine"
    assert wf.groups[gid].max_iterations == 5
    assert wf.steps["loop1"].group_id == gid
  end

  test "execute_now completes step synchronously", %{workflow_id: wid} do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)

    assert {:ok, step} =
             WorkflowServer.execute_now(wid, %{
               step_id: "now",
               step_name: "now",
               url: "http://example/now"
             })

    assert step.status == :completed
    assert step.output == %{}

    assert {:ok, wf} = WorkflowServer.get_state(wid)
    assert wf.steps["now"].status == :completed
  end
end
