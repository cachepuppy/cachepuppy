defmodule CachePuppy.Test.WorkflowHelpers do
  @moduledoc false

  import ExUnit.Assertions

  alias CachePuppyCore.Graph.Builder
  alias CachePuppyCore.WorkflowServer

  @spec wait_for_completion(String.t(), keyword()) :: CachePuppyCore.Workflow.t()
  def wait_for_completion(workflow_id, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 10_000)
    interval_ms = Keyword.get(opts, :interval_ms, 25)
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms

    do_wait_for_completion(workflow_id, deadline_ms, interval_ms)
  end

  @spec subscribe_to_workflow(String.t()) :: :ok | {:error, term()}
  def subscribe_to_workflow(workflow_id) when is_binary(workflow_id) do
    Phoenix.PubSub.subscribe(CachePuppyCore.PubSub, "workflow:" <> workflow_id)
  end

  @spec collect_broadcasts(String.t()) :: [map()]
  def collect_broadcasts(_workflow_id) do
    do_collect_broadcasts([])
  end

  @spec assert_graph_shape(String.t(), map()) :: :ok
  def assert_graph_shape(workflow_id, expected) do
    {:ok, workflow} = WorkflowServer.get_state(workflow_id)
    graph = Builder.build(workflow)

    if node_count = expected[:node_count] do
      assert length(graph.nodes) == node_count
    end

    if edge_count = expected[:edge_count] do
      assert length(graph.edges) == edge_count
    end

    if edge_types = expected[:edge_types] do
      actual_types = graph.edges |> Enum.map(& &1["type"]) |> Enum.sort()
      assert actual_types == Enum.sort(edge_types)
    end

    :ok
  end

  defp do_wait_for_completion(workflow_id, deadline_ms, interval_ms) do
    {:ok, workflow} = WorkflowServer.get_state(workflow_id)

    cond do
      workflow.status == :completed ->
        workflow

      workflow.status == :failed ->
        flunk("workflow #{workflow_id} failed: #{inspect(workflow.failure_reason)}")

      System.monotonic_time(:millisecond) > deadline_ms ->
        flunk("workflow #{workflow_id} did not complete before timeout")

      true ->
        Process.sleep(interval_ms)
        do_wait_for_completion(workflow_id, deadline_ms, interval_ms)
    end
  end

  defp do_collect_broadcasts(acc) do
    receive do
      {:graph_diff, diff} -> do_collect_broadcasts([diff | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
