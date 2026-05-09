defmodule CachePuppyCore.Graph.Node do
  @moduledoc false

  alias CachePuppyCore.Workflow.{ParallelGroup, Step}

  @type t :: map()

  @spec from_step(Step.t()) :: t()
  def from_step(%Step{} = step) do
    %{
      "nodeId" => step.step_id,
      "stepName" => step.step_name,
      "type" => step_type(step),
      "status" => atom_to_string(step.status),
      "groupId" => step.group_id,
      "iterationNumber" => nil,
      "parentIds" => step.parent_ids,
      "input" => step.input,
      "output" => step.output,
      "insertedAt" => iso(step.inserted_at),
      "startedAt" => iso(step.started_at),
      "completedAt" => iso(step.completed_at),
      "retryCount" => step.retry_count,
      "error" => sanitize_json_value(step.execution_error)
    }
  end

  @spec from_parallel_group(ParallelGroup.t(), [String.t()]) :: t()
  def from_parallel_group(%ParallelGroup{} = group, parent_ids) do
    %{
      "nodeId" => group.group_id,
      "type" => "parallel_group",
      "status" => atom_to_string(group.status),
      "totalBranches" => group.total_branches,
      "completedBranches" => group.completed_branches,
      "parentIds" => parent_ids
    }
  end

  defp step_type(%Step{group_type: :parallel_branch}), do: "parallel_branch"
  defp step_type(%Step{group_type: :parallel_merge}), do: "merge"
  defp step_type(%Step{}), do: "serial"

  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso(_), do: nil

  defp sanitize_json_value(nil), do: nil
  defp sanitize_json_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp sanitize_json_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)

  defp sanitize_json_value(%_{} = struct),
    do: struct |> Map.from_struct() |> sanitize_json_value()

  defp sanitize_json_value(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {k, sanitize_json_value(v)} end)
    |> Map.new()
  end

  defp sanitize_json_value(list) when is_list(list), do: Enum.map(list, &sanitize_json_value/1)

  defp sanitize_json_value(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&sanitize_json_value/1)

  defp sanitize_json_value(value), do: value

  defp atom_to_string(v) when is_atom(v), do: Atom.to_string(v)
  defp atom_to_string(v), do: v
end
