defmodule CachePuppyCore.Orchestrator.LoopHandler do
  @moduledoc false

  alias CachePuppyCore.Orchestrator.ConditionEvaluator
  alias CachePuppyCore.Workflow
  alias CachePuppyCore.Workflow.{LoopGroup, LoopIteration, Step}

  @spec on_step_completed(Workflow.t(), Step.t()) :: Workflow.t()
  def on_step_completed(
        %Workflow{} = workflow,
        %Step{group_type: :loop_iteration, group_id: gid} = step
      )
      when is_binary(gid) do
    case Map.get(workflow.groups, gid) do
      %LoopGroup{} = group ->
        iter = %LoopIteration{
          step_id: step.step_id,
          input: step.input,
          output: step.output,
          status: :completed
        }

        group = %{
          group
          | iterations: group.iterations ++ [iter],
            current_iteration: group.current_iteration + 1
        }

        should_continue? =
          group.current_iteration < group.max_iterations and
            match?(
              {:ok, true},
              ConditionEvaluator.evaluate(group.continue_if, output_map(step.output))
            )

        if should_continue? do
          create_next_iteration(workflow, group, step)
        else
          groups = Map.put(workflow.groups, gid, %{group | status: :completed})
          %{workflow | groups: groups}
        end

      _ ->
        workflow
    end
  end

  def on_step_completed(workflow, _step), do: workflow

  defp create_next_iteration(workflow, group, completed_step) do
    %Step{} = template = Map.fetch!(workflow.steps, group.template_step_id)
    step_id = "loop-iter-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    next_step = %Step{
      template
      | step_id: step_id,
        status: :pending,
        retry_count: 0,
        input: nil,
        output: nil,
        execution_error: nil,
        parent_ids: [completed_step.step_id],
        group_id: group.group_id,
        group_type: :loop_iteration,
        inserted_at: DateTime.utc_now(),
        started_at: nil,
        completed_at: nil
    }

    groups = Map.put(workflow.groups, group.group_id, group)

    workflow
    |> Map.put(:groups, groups)
    |> Map.put(:steps, Map.put(workflow.steps, next_step.step_id, next_step))
    |> Map.put(:serial_tail_step_id, next_step.step_id)
  end

  defp output_map(%{} = output), do: output
  defp output_map(_), do: %{}
end
