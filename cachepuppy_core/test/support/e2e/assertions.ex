defmodule CachePuppy.Test.E2E.Assertions do
  @moduledoc false

  import ExUnit.Assertions

  alias CachePuppyCore.Graph.Builder
  alias CachePuppyCore.WorkflowServer
  alias CachePuppy.Test.E2E.CachePuppyHTTP

  @spec wait_for_completion(String.t(), String.t(), keyword()) :: map()
  def wait_for_completion(api_base, workflow_id, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 12_000)
    interval_ms = Keyword.get(opts, :interval_ms, 50)
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    do_wait(api_base, workflow_id, deadline, interval_ms)
  end

  @spec assert_all_steps_completed(map()) :: :ok
  def assert_all_steps_completed(workflow_state) do
    assert workflow_state["status"] == "completed"
    assert Enum.all?(workflow_state["steps"], &(&1["status"] == "completed"))
    :ok
  end

  @spec assert_graph_shape(String.t(), map()) :: :ok
  def assert_graph_shape(workflow_id, expected) do
    {:ok, workflow} = WorkflowServer.get_state(workflow_id)
    graph = Builder.build(workflow)

    if n = expected[:node_count], do: assert(length(graph.nodes) == n)
    if e = expected[:edge_count], do: assert(length(graph.edges) == e)

    if types = expected[:edge_types] do
      actual = graph.edges |> Enum.map(& &1["type"]) |> Enum.sort()
      assert actual == Enum.sort(types)
    end

    :ok
  end

  defp do_wait(api_base, workflow_id, deadline, interval_ms) do
    state = CachePuppyHTTP.get_workflow(api_base, workflow_id)

    cond do
      state["status"] == "completed" ->
        state

      state["status"] == "failed" ->
        flunk("workflow failed: #{inspect(state)}")

      System.monotonic_time(:millisecond) > deadline ->
        flunk("timeout waiting for workflow completion: #{workflow_id}")

      true ->
        Process.sleep(interval_ms)
        do_wait(api_base, workflow_id, deadline, interval_ms)
    end
  end
end
