defmodule CachePuppyCoreWeb.WorkflowJSON do
  @moduledoc false

  alias CachePuppyCore.Workflow
  alias CachePuppyCore.Workflow.{ParallelGroup, Step}

  def created(%Workflow{} = workflow) do
    %{
      "workflowId" => workflow.id,
      "name" => workflow.name,
      "status" => to_status(workflow.status)
    }
  end

  def workflow_state(%Workflow{} = workflow) do
    %{
      "workflowId" => workflow.id,
      "name" => workflow.name,
      "status" => to_status(workflow.status),
      "steps" => workflow.steps |> Map.values() |> Enum.map(&step_json/1),
      "groups" => workflow.groups |> Map.values() |> Enum.map(&group_json/1)
    }
  end

  def step_created(%Step{} = step) do
    %{
      "stepId" => step.step_id,
      "stepName" => step.step_name,
      "status" => to_status(step.status)
    }
  end

  def parallel_created(group_id, steps, merge_step) do
    %{
      "groupId" => group_id,
      "totalBranches" => length(steps),
      "steps" => Enum.map(steps, &step_json/1),
      "mergeStep" => step_json(merge_step)
    }
  end

  def workflow_status(%Workflow{} = workflow) do
    %{"workflowId" => workflow.id, "status" => to_status(workflow.status)}
  end

  defp step_json(%Step{} = step) do
    %{
      "stepId" => step.step_id,
      "stepName" => step.step_name,
      "url" => step.url,
      "method" => String.downcase(step.method || "post"),
      "data" => step.data,
      "status" => to_status(step.status),
      "successCodes" => step.success_codes,
      "maxRetries" => step.max_retries,
      "retryCount" => step.retry_count,
      "input" => step.input,
      "output" => step.output,
      "parentIds" => step.parent_ids,
      "groupId" => step.group_id
    }
  end

  defp group_json(%ParallelGroup{} = group) do
    %{
      "type" => "parallel",
      "groupId" => group.group_id,
      "totalBranches" => group.total_branches,
      "completedBranches" => completed_branch_count(group),
      "collectedOutputs" => group.collected_outputs,
      "mergeStepId" => group.merge_step_id,
      "status" => to_status(group.status),
      "mergeArmed" => group.merge_armed,
      "branchRootStepIds" => group.branch_root_step_ids,
      "branchTerminalStepIds" => group.branch_terminal_step_ids
    }
  end

  defp to_status(status) when is_atom(status), do: Atom.to_string(status)
  defp to_status(status), do: status

  defp completed_branch_count(group) do
    group.branch_terminal_step_ids
    |> map_size()
  end
end
