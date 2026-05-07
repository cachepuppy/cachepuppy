defmodule CachePuppyCore.Graph.Broadcaster do
  @moduledoc false

  alias CachePuppyCore.Graph.{Builder, Differ, Snapshot}
  alias CachePuppyCore.Workflow.WorkflowStore

  @spec broadcast(String.t()) :: :ok
  def broadcast(workflow_id) when is_binary(workflow_id) do
    case WorkflowStore.get(workflow_id) do
      {:ok, workflow} ->
        current = Builder.build(workflow)
        previous = Snapshot.get(workflow)
        diff = Differ.diff(previous, current)

        if Differ.empty_diff?(diff) do
          :ok
        else
          :ok =
            Phoenix.PubSub.broadcast(
              CachePuppyCore.PubSub,
              "workflow:" <> workflow_id,
              {:graph_diff, diff}
            )

          workflow
          |> Snapshot.put(current)
          |> then(&WorkflowStore.put(workflow_id, &1))
        end

      :not_found ->
        :ok
    end
  end
end
