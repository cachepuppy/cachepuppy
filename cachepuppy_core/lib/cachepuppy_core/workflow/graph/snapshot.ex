defmodule CachePuppyCore.Graph.Snapshot do
  @moduledoc false

  alias CachePuppyCore.Graph
  alias CachePuppyCore.Workflow

  @spec get(Workflow.t()) :: Graph.t() | nil
  def get(%Workflow{} = workflow) do
    Map.get(workflow, :graph_snapshot)
  end

  @spec put(Workflow.t(), Graph.t()) :: Workflow.t()
  def put(%Workflow{} = workflow, %Graph{} = graph) do
    Map.put(workflow, :graph_snapshot, graph)
  end
end
