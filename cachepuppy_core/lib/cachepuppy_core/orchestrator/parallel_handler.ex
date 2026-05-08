defmodule CachePuppyCore.Orchestrator.ParallelHandler do
  @moduledoc false

  alias CachePuppyCore.Workflow
  alias CachePuppyCore.Workflow.ParallelGroup

  @spec on_step_completed(Workflow.t(), CachePuppyCore.Workflow.Step.t()) :: Workflow.t()
  def on_step_completed(%Workflow{} = workflow, step) do
    case step.group_type do
      :parallel_branch ->
        update_branch_completion(workflow, step)

      :parallel_merge ->
        mark_group_completed(workflow, step.group_id)

      _ ->
        workflow
    end
  end

  @spec mark_group_failed(Workflow.t(), String.t() | nil) :: Workflow.t()
  def mark_group_failed(%Workflow{} = workflow, nil), do: workflow

  def mark_group_failed(%Workflow{groups: groups} = workflow, group_id) do
    case Map.get(groups, group_id) do
      %ParallelGroup{} = g ->
        %{workflow | groups: Map.put(groups, group_id, %{g | status: :failed})}

      _ ->
        workflow
    end
  end

  defp update_branch_completion(%Workflow{groups: groups} = workflow, step) do
    case Map.get(groups, step.group_id) do
      %ParallelGroup{} ->
        workflow

      _ ->
        workflow
    end
  end

  defp mark_group_completed(%Workflow{groups: groups} = workflow, group_id)
       when is_binary(group_id) do
    case Map.get(groups, group_id) do
      %ParallelGroup{} = g ->
        %{workflow | groups: Map.put(groups, group_id, %{g | status: :completed})}

      _ ->
        workflow
    end
  end

  defp mark_group_completed(workflow, _), do: workflow
end
