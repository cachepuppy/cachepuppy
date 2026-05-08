defmodule CachePuppyCore.Orchestrator do
  @moduledoc false

  alias CachePuppyCore.Orchestrator.{LoopHandler, ParallelHandler, SerialHandler}
  alias CachePuppyCore.Execution.StepExecutor
  alias CachePuppyCore.Workflow
  alias CachePuppyCore.Workflow.{ParallelGroup, Step}

  @type action :: {:execute_step, Step.t(), keyword()}

  @spec advance(Workflow.t()) :: {Workflow.t(), [action()]}
  def advance(%Workflow{status: s} = workflow) when s in [:failed, :completed], do: {workflow, []}

  def advance(%Workflow{} = workflow) do
    workflow =
      case workflow.status do
        :pending -> %{workflow | status: :running}
        _ -> workflow
      end

    runnable =
      workflow
      |> SerialHandler.runnable_steps()
      |> Enum.map(fn step ->
        opts =
          case merge_data_for_step(workflow, step) do
            :omit -> []
            merge_data -> [merge_data: merge_data]
          end

        {:execute_step, step, opts}
      end)

    workflow =
      if runnable == [] and terminal_success?(workflow) do
        %{workflow | status: :completed}
      else
        workflow
      end

    {workflow, runnable}
  end

  @spec on_step_result(Workflow.t(), String.t(), StepExecutor.success() | StepExecutor.error()) ::
          {Workflow.t(), [action()]}
  def on_step_result(%Workflow{} = workflow, step_id, result) do
    workflow = %{workflow | active_step_ids: MapSet.delete(workflow.active_step_ids, step_id)}

    case Map.get(workflow.steps, step_id) do
      nil ->
        {workflow, []}

      step ->
        case result do
          {:ok, %{body: body, step: exec_step}} ->
            completed = %{
              step
              | status: :completed,
                output: body,
                retry_count: exec_step.retry_count,
                execution_error: nil,
                completed_at: DateTime.utc_now()
            }

            workflow =
              workflow
              |> put_step(completed)
              |> ParallelHandler.on_step_completed(completed)
              |> LoopHandler.on_step_completed(completed)
              |> touch()

            advance(workflow)

          {:error, reason} ->
            failed = %{
              step
              | status: :failed,
                execution_error: reason,
                completed_at: DateTime.utc_now()
            }

            workflow =
              workflow
              |> put_step(failed)
              |> ParallelHandler.mark_group_failed(step.group_id)
              |> Map.put(:status, :failed)
              |> Map.put(:failure_reason, reason)
              |> touch()

            {workflow, []}
        end
    end
  end

  @spec mark_step_running(Workflow.t(), String.t()) :: Workflow.t()
  def mark_step_running(%Workflow{} = workflow, step_id) do
    case Map.get(workflow.steps, step_id) do
      nil ->
        workflow

      step ->
        running = %{step | status: :running, started_at: DateTime.utc_now(), input: step.data}

        workflow
        |> put_step(running)
        |> Map.put(:active_step_ids, MapSet.put(workflow.active_step_ids, step_id))
        |> touch()
    end
  end

  defp merge_data_for_step(workflow, %Step{group_type: :parallel_merge, group_id: gid}) do
    case Map.get(workflow.groups, gid) do
      %ParallelGroup{} = g ->
        g.branch_terminal_step_ids
        |> Enum.sort_by(fn {branch_id, _} -> branch_id end)
        |> Enum.map(fn {_branch_id, terminal_id} ->
          term_step = Map.get(workflow.steps, terminal_id)
          %{"step_id" => terminal_id, "output" => term_step && term_step.output}
        end)
      _ -> :omit
    end
  end

  defp merge_data_for_step(_workflow, _step), do: :omit

  defp terminal_success?(workflow) do
    workflow.status not in [:failed, :completed] and
      map_size(workflow.steps) > 0 and
      Enum.all?(workflow.steps, fn {_id, step} -> step.status == :completed end) and
      Enum.all?(workflow.groups, fn {_id, group} -> Map.get(group, :status) == :completed end) and
      workflow.active_step_ids == MapSet.new()
  end

  defp put_step(%Workflow{steps: steps} = workflow, %Step{} = step) do
    %{workflow | steps: Map.put(steps, step.step_id, step)}
  end

  defp touch(%Workflow{} = workflow) do
    %{workflow | updated_at: DateTime.utc_now()}
  end
end
