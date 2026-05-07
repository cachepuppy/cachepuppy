defmodule CachePuppy.Test.E2E.Assertions do
  @moduledoc false

  import ExUnit.Assertions

  alias CachePuppyCore.Graph.Builder
  alias CachePuppyCore.WorkflowServer

  @spec wait_for_completion(String.t(), String.t(), keyword()) :: map()
  def wait_for_completion(api_base, workflow_id, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 12_000)
    interval_ms = Keyword.get(opts, :interval_ms, 50)
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_completion(api_base, workflow_id, deadline_ms, interval_ms)
  end

  @spec assert_graph_shape(String.t(), map()) :: :ok
  def assert_graph_shape(workflow_id, expected) do
    {:ok, workflow} = WorkflowServer.get_state(workflow_id)
    graph = Builder.build(workflow)

    if node_count = expected[:node_count], do: assert(length(graph.nodes) == node_count)
    if edge_count = expected[:edge_count], do: assert(length(graph.edges) == edge_count)

    if edge_types = expected[:edge_types] do
      actual_types = graph.edges |> Enum.map(& &1["type"]) |> Enum.sort()
      assert actual_types == Enum.sort(edge_types)
    end

    :ok
  end

  defp do_wait_for_completion(api_base, workflow_id, deadline_ms, interval_ms) do
    workflow = get_workflow!(api_base, workflow_id)

    cond do
      workflow["status"] == "completed" ->
        workflow

      workflow["status"] == "failed" ->
        flunk("workflow #{workflow_id} failed: #{inspect(workflow)}")

      System.monotonic_time(:millisecond) > deadline_ms ->
        flunk("workflow #{workflow_id} did not complete before timeout")

      true ->
        Process.sleep(interval_ms)
        do_wait_for_completion(api_base, workflow_id, deadline_ms, interval_ms)
    end
  end

  defp get_workflow!(api_base, workflow_id) do
    url = api_base <> "/api/workflows/" <> workflow_id

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        body

      {:ok, %{status: status, body: body}} ->
        raise "GET #{url} expected 200, got #{status}: #{inspect(body)}"

      {:error, reason} ->
        raise "GET #{url} failed: #{inspect(reason)}"
    end
  end
end
