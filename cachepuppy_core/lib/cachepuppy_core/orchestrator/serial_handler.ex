defmodule CachePuppyCore.Orchestrator.SerialHandler do
  @moduledoc false

  alias CachePuppyCore.Workflow
  alias CachePuppyCore.Workflow.{ParallelGroup, Step}

  @spec runnable_steps(Workflow.t()) :: [Step.t()]
  def runnable_steps(%Workflow{} = workflow) do
    completed = completed_step_ids(workflow)

    workflow.steps
    |> Map.values()
    |> Enum.filter(fn step ->
      step.status == :pending and
        not MapSet.member?(workflow.active_step_ids, step.step_id) and
        Enum.all?(step.parent_ids, &MapSet.member?(completed, &1)) and
        merge_ready?(workflow, step)
    end)
    |> Enum.sort_by(&(&1.inserted_at || ~U[1970-01-01 00:00:00Z]), DateTime)
  end

  defp completed_step_ids(workflow) do
    workflow.steps
    |> Enum.reduce(MapSet.new(), fn {id, step}, acc ->
      if step.status == :completed, do: MapSet.put(acc, id), else: acc
    end)
  end

  defp merge_ready?(%Workflow{} = workflow, %Step{group_type: :parallel_merge, group_id: gid}) do
    case Map.get(workflow.groups, gid) do
      %ParallelGroup{} = group ->
        all_branches_closed?(group) and
          Enum.all?(Map.values(group.branch_terminal_step_ids), fn terminal_id ->
            case Map.get(workflow.steps, terminal_id) do
              %Step{status: :completed} -> true
              _ -> false
            end
          end)

      _ ->
        false
    end
  end

  defp merge_ready?(_workflow, _step), do: true

  defp all_branches_closed?(%ParallelGroup{} = group) do
    group.branch_statuses
    |> Map.values()
    |> Enum.all?(&(&1 == :closed))
  end
end
