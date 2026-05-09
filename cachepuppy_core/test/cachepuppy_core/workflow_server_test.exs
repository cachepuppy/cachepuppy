defmodule CachePuppyCore.WorkflowServerTest do
  use ExUnit.Case, async: false

  alias CachePuppyCore.Workflow.ParallelGroup
  alias CachePuppyCore.Workflow.WorkflowStore
  alias CachePuppyCore.{WorkflowManager, WorkflowServer}

  defmodule ExecutorStub do
    @moduledoc false

    def execute(step, _workflow_id, opts) do
      if pid = Keyword.get(opts, :test_pid) do
        send(pid, {:executed_step, step.step_id, Keyword.get(opts, :merge_data, :omit)})
      end

      agent = Keyword.fetch!(opts, :response_agent)

      Agent.get_and_update(agent, fn
        [h | t] -> {h, t}
        [] -> {{:ok, %{status_code: 200, body: %{}, step: %{step | retry_count: 0}}}, []}
      end)
    end
  end

  setup do
    wid = "wf-test-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    old_mod = Application.get_env(:cachepuppy_core, :workflow_step_executor_module)
    old_opts = Application.get_env(:cachepuppy_core, :workflow_step_executor_opts)
    agent = start_supervised!({Agent, fn -> [] end})

    Application.put_env(:cachepuppy_core, :workflow_step_executor_module, ExecutorStub)

    Application.put_env(
      :cachepuppy_core,
      :workflow_step_executor_opts,
      test_pid: self(),
      response_agent: agent,
      skip_sleep: true
    )

    on_exit(fn ->
      WorkflowStore.delete(wid)

      if old_mod,
        do: Application.put_env(:cachepuppy_core, :workflow_step_executor_module, old_mod),
        else: Application.delete_env(:cachepuppy_core, :workflow_step_executor_module)

      if old_opts,
        do: Application.put_env(:cachepuppy_core, :workflow_step_executor_opts, old_opts),
        else: Application.delete_env(:cachepuppy_core, :workflow_step_executor_opts)
    end)

    {:ok, workflow_id: wid, response_agent: agent}
  end

  defp set_responses(agent, responses) do
    Agent.update(agent, fn _ -> responses end)
  end

  defp await_step_execution(step_id) do
    assert_receive {:executed_step, ^step_id, _merge_data}
  end

  defp wait_for(assertion_fun, attempts \\ 20)
  defp wait_for(assertion_fun, 0), do: assertion_fun.()

  defp wait_for(assertion_fun, attempts) do
    try do
      assertion_fun.()
    rescue
      ExUnit.AssertionError ->
        Process.sleep(10)
        wait_for(assertion_fun, attempts - 1)
    end
  end

  test "get_state on fresh workflow is pending with empty steps", %{workflow_id: wid} do
    assert {:ok, _pid} = WorkflowManager.ensure_started(wid)
    assert {:ok, wf} = WorkflowServer.get_state(wid)
    assert wf.id == wid
    assert wf.status == :running
    assert wf.steps == %{}
  end

  test "add_step triggers orchestrator and executes step asynchronously", %{
    workflow_id: wid,
    response_agent: agent
  } do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)

    set_responses(agent, [
      {:ok,
       %{
         status_code: 200,
         body: %{"ok" => true},
         step: %CachePuppyCore.Workflow.Step{retry_count: 0}
       }}
    ])

    s1 = %{step_id: "a", step_name: "one", url: "http://example/a"}
    assert {:ok, _} = WorkflowServer.add_step(wid, s1)
    await_step_execution("a")

    wait_for(fn ->
      assert {:ok, wf} = WorkflowServer.get_state(wid)
      assert wf.status in [:running, :completed]
      assert wf.serial_tail_step_id == "a"
      assert wf.steps["a"].status == :completed
    end)
  end

  test "merge_now returns error for unknown merge step", %{workflow_id: wid} do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)
    assert {:error, :not_found} = WorkflowServer.merge_now(wid, "missing_merge")
  end

  test "parallel merge waits for explicit merge_now arming", %{
    workflow_id: wid,
    response_agent: agent
  } do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)

    set_responses(agent, [
      {:ok,
       %{
         status_code: 200,
         body: %{"p1" => 1},
         step: %CachePuppyCore.Workflow.Step{retry_count: 0}
       }},
      {:ok,
       %{
         status_code: 200,
         body: %{"p2" => 1},
         step: %CachePuppyCore.Workflow.Step{retry_count: 0}
       }},
      {:ok,
       %{
         status_code: 200,
         body: %{"merged" => true},
         step: %CachePuppyCore.Workflow.Step{retry_count: 0}
       }}
    ])

    branches = [
      %{step_id: "p1", step_name: "b1", url: "http://example/p1"},
      %{step_id: "p2", step_name: "b2", url: "http://example/p2"}
    ]

    merge = %{step_id: "m", step_name: "merge", url: "http://example/m"}
    assert {:ok, gid, _, _} = WorkflowServer.add_parallel(wid, branches, merge)

    assert {:ok, wf} = WorkflowServer.get_state(wid)
    assert %ParallelGroup{} = wf.groups[gid]

    await_step_execution("p1")
    await_step_execution("p2")

    refute_receive {:executed_step, "m", _}

    assert {:ok, _group} = WorkflowServer.merge_now(wid, "m")
    assert_receive {:executed_step, "m", merge_data}
    assert is_list(merge_data)
  end

  test "invoking_step_id attaches new step to invoking parallel branch", %{workflow_id: wid} do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)

    branches = [
      %{step_id: "p1", step_name: "b1", url: "http://example/p1"},
      %{step_id: "p2", step_name: "b2", url: "http://example/p2"}
    ]

    merge = %{step_id: "m", step_name: "merge", url: "http://example/m"}
    assert {:ok, gid, _, _} = WorkflowServer.add_parallel(wid, branches, merge)

    assert {:ok, step} =
             WorkflowServer.add_step(
               wid,
               %{step_id: "p1_next", step_name: "next", url: "http://example/p1_next"},
               invoking_step_id: "p1"
             )

    assert step.parent_ids == ["p1"]
    assert step.group_id == gid
    assert step.group_type == :parallel_branch

    assert {:ok, wf} = WorkflowServer.get_state(wid)
    assert wf.groups[gid].branch_terminal_step_ids["p1"] == "p1_next"
  end

  test "nested add_parallel from branch records parent group and updates parent terminal", %{
    workflow_id: wid
  } do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)

    branches = [
      %{step_id: "p1", step_name: "b1", url: "http://example/p1"},
      %{step_id: "p2", step_name: "b2", url: "http://example/p2"}
    ]

    merge = %{step_id: "m", step_name: "merge", url: "http://example/m"}
    assert {:ok, outer_gid, _, _} = WorkflowServer.add_parallel(wid, branches, merge)

    inner_steps = [
      %{step_id: "s1", step_name: "search", url: "http://example/s1"},
      %{step_id: "s2", step_name: "search", url: "http://example/s2"}
    ]

    inner_merge = %{step_id: "m2", step_name: "collect", url: "http://example/m2"}

    assert {:ok, inner_gid, _, _} =
             WorkflowServer.add_parallel(wid, inner_steps, inner_merge, invoking_step_id: "p1")

    assert {:ok, wf} = WorkflowServer.get_state(wid)
    assert wf.groups[inner_gid].parent_group_id == outer_gid
    assert wf.groups[outer_gid].branch_terminal_step_ids["p1"] == "m2"
  end

  test "outer merge parents include nested merge terminal for invoking branch", %{
    workflow_id: wid
  } do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)

    branches = [
      %{step_id: "p1", step_name: "b1", url: "http://example/p1"},
      %{step_id: "p2", step_name: "b2", url: "http://example/p2"}
    ]

    merge = %{step_id: "m", step_name: "merge", url: "http://example/m"}
    assert {:ok, _outer_gid, _, _} = WorkflowServer.add_parallel(wid, branches, merge)

    assert {:ok, _inner_gid, _, _} =
             WorkflowServer.add_parallel(
               wid,
               [
                 %{step_id: "s1", step_name: "search", url: "http://example/s1"},
                 %{step_id: "s2", step_name: "search", url: "http://example/s2"}
               ],
               %{step_id: "m2", step_name: "collect", url: "http://example/m2"},
               invoking_step_id: "p1"
             )

    assert {:ok, _} = WorkflowServer.merge_now(wid, "m")

    assert {:ok, wf_after} = WorkflowServer.get_state(wid)
    assert Enum.sort(wf_after.steps["m"].parent_ids) == ["m2", "p2"]
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

  test "add_loop starts first iteration and continue_if false completes loop", %{
    workflow_id: wid,
    response_agent: agent
  } do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)

    set_responses(agent, [
      {:ok,
       %{
         status_code: 200,
         body: %{"score" => 0.9},
         step: %CachePuppyCore.Workflow.Step{retry_count: 0}
       }}
    ])

    step = %{step_id: "loop1", step_name: "refine", url: "http://example/r"}
    assert {:ok, gid} = WorkflowServer.add_loop(wid, step, "result.score < 0.8", 5)
    await_step_execution("loop1")

    wait_for(fn ->
      assert {:ok, wf} = WorkflowServer.get_state(wid)
      assert wf.groups[gid].status == :completed
    end)
  end

  test "execute_now returns synchronously and does not trigger orchestrator", %{
    workflow_id: wid,
    response_agent: agent
  } do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)

    set_responses(agent, [
      {:ok,
       %{
         status_code: 200,
         body: %{"immediate" => true},
         step: %CachePuppyCore.Workflow.Step{retry_count: 0}
       }}
    ])

    assert {:ok, step} =
             WorkflowServer.execute_now(wid, %{
               step_id: "now",
               step_name: "now",
               url: "http://example/now"
             })

    assert_receive {:executed_step, "now", nil}
    assert step.status == :completed
    assert step.output == %{"immediate" => true}

    assert {:ok, wf} = WorkflowServer.get_state(wid)
    assert wf.steps["now"].status == :completed
  end

  test "add_step broadcasts graph diff over pubsub", %{workflow_id: wid, response_agent: agent} do
    assert {:ok, _} = WorkflowManager.ensure_started(wid)

    set_responses(agent, [
      {:ok, %{status_code: 200, body: %{}, step: %CachePuppyCore.Workflow.Step{retry_count: 0}}}
    ])

    :ok = Phoenix.PubSub.subscribe(CachePuppyCore.PubSub, "workflow:" <> wid)

    s1 = %{step_id: "g1", step_name: "graph", url: "http://example/graph"}
    assert {:ok, _} = WorkflowServer.add_step(wid, s1)

    assert_receive {:graph_diff, diff}
    assert diff["workflowId"] == wid
  end
end
