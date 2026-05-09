defmodule CachePuppyCore.Execution.Payload do
  @moduledoc false

  alias CachePuppyCore.Workflow.Step

  @doc """
  Builds the JSON body for POST to a developer step endpoint.

  When `merge_data` is supplied (including `[]`), includes `"mergeData"` in `"input"`.
  Pass `:omit` (default) to exclude `mergeData` entirely.
  """
  @spec build_body(String.t(), Step.t(), :omit | term()) :: map()
  def build_body(workflow_id, %Step{} = step, merge_data \\ :omit)
      when is_binary(workflow_id) do
    input =
      case merge_data do
        :omit ->
          %{"workflowId" => workflow_id, "stepId" => step.step_id, "data" => step.data}

        md ->
          %{
            "workflowId" => workflow_id,
            "stepId" => step.step_id,
            "data" => step.data,
            "mergeData" => md
          }
      end

    %{"input" => input}
  end

  @spec build_headers(String.t(), Step.t()) :: [{String.t(), String.t()}]
  def build_headers(workflow_id, %Step{} = step) when is_binary(workflow_id) do
    [
      {"content-type", "application/json"},
      {"x-cachepuppy-step", step.step_name},
      {"x-cachepuppy-step-id", step.step_id},
      {"x-cachepuppy-workflow", workflow_id}
    ]
  end
end
