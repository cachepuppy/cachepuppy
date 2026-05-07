defmodule CachePuppyCore.Orchestrator.SerialHandler do
  @moduledoc false

  alias CachePuppyCore.Workflow
  alias CachePuppyCore.Workflow.Step

  @spec runnable_steps(Workflow.t()) :: [Step.t()]
  def runnable_steps(%Workflow{} = workflow) do
    completed = completed_step_ids(workflow)

    workflow.steps
    |> Map.values()
    |> Enum.filter(fn step ->
      step.status == :pending and
        not MapSet.member?(workflow.active_step_ids, step.step_id) and
        Enum.all?(step.parent_ids, &MapSet.member?(completed, &1))
    end)
    |> Enum.sort_by(&(&1.inserted_at || ~U[1970-01-01 00:00:00Z]), DateTime)
  end

  defp completed_step_ids(workflow) do
    workflow.steps
    |> Enum.reduce(MapSet.new(), fn {id, step}, acc ->
      if step.status == :completed, do: MapSet.put(acc, id), else: acc
    end)
  end
end
