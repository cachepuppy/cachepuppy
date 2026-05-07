defmodule CachePuppyCore.Graph.Differ do
  @moduledoc false

  alias CachePuppyCore.Graph

  @watched_fields ~w(status output error retryCount startedAt completedAt)

  @spec diff(Graph.t() | nil, Graph.t()) :: map()
  def diff(nil, %Graph{} = current) do
    %{
      "workflowId" => current.workflow_id,
      "changedNodes" => [],
      "addedNodes" => current.nodes,
      "addedEdges" => current.edges,
      "workflowStatus" => current.status,
      "updatedAt" => current.updated_at
    }
  end

  def diff(%Graph{} = prev, %Graph{} = current) do
    prev_nodes = index_by_node_id(prev.nodes)
    prev_edges = MapSet.new(Enum.map(prev.edges, &edge_key/1))

    added_nodes =
      Enum.filter(current.nodes, fn node ->
        not Map.has_key?(prev_nodes, node["nodeId"])
      end)

    changed_nodes =
      Enum.filter(current.nodes, fn node ->
        case Map.get(prev_nodes, node["nodeId"]) do
          nil -> false
          old -> changed_node?(old, node)
        end
      end)

    added_edges =
      Enum.filter(current.edges, fn edge ->
        not MapSet.member?(prev_edges, edge_key(edge))
      end)

    %{
      "workflowId" => current.workflow_id,
      "changedNodes" => changed_nodes,
      "addedNodes" => added_nodes,
      "addedEdges" => added_edges,
      "workflowStatus" => current.status,
      "updatedAt" => current.updated_at
    }
  end

  @spec empty_diff?(map()) :: boolean()
  def empty_diff?(diff) when is_map(diff) do
    Enum.empty?(Map.get(diff, "changedNodes", [])) and
      Enum.empty?(Map.get(diff, "addedNodes", [])) and
      Enum.empty?(Map.get(diff, "addedEdges", []))
  end

  defp changed_node?(old, new) do
    Enum.any?(@watched_fields, fn key -> Map.get(old, key) != Map.get(new, key) end)
  end

  defp index_by_node_id(nodes) do
    Map.new(nodes, &{&1["nodeId"], &1})
  end

  defp edge_key(edge), do: {edge["from"], edge["to"], edge["type"]}
end
