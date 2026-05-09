defmodule CachePuppyCore.Graph.Builder do
  @moduledoc false

  alias CachePuppyCore.Graph
  alias CachePuppyCore.Graph.{Edge, Node}
  alias CachePuppyCore.Workflow
  alias CachePuppyCore.Workflow.{ParallelGroup, Step}

  @spec build(Workflow.t()) :: Graph.t()
  def build(%Workflow{} = workflow) do
    step_nodes = build_step_nodes(workflow)
    group_nodes = build_group_nodes(workflow)
    edges = build_edges(workflow)

    %Graph{
      workflow_id: workflow.id,
      name: workflow.name,
      status: atom_to_string(workflow.status),
      nodes: step_nodes ++ group_nodes,
      edges: Enum.uniq(edges),
      updated_at: iso(workflow.updated_at || workflow.inserted_at || DateTime.utc_now())
    }
  end

  defp build_step_nodes(workflow) do
    workflow.steps
    |> Map.values()
    |> Enum.map(&Node.from_step/1)
  end

  defp build_group_nodes(workflow) do
    workflow.groups
    |> Map.values()
    |> Enum.map(fn
      %ParallelGroup{} = group ->
        Node.from_parallel_group(group, parallel_parent_ids(workflow, group.group_id))
    end)
  end

  defp build_edges(workflow) do
    serial_edges = serial_edges(workflow)
    parallel_edges = parallel_edges(workflow)
    serial_edges ++ parallel_edges
  end

  defp serial_edges(workflow) do
    workflow.steps
    |> Map.values()
    |> Enum.flat_map(fn %Step{step_id: sid, parent_ids: parents} ->
      Enum.map(parents, fn pid -> Edge.build(pid, sid, :serial) end)
    end)
  end

  defp parallel_edges(workflow) do
    workflow.groups
    |> Map.values()
    |> Enum.flat_map(fn
      %ParallelGroup{} = pg ->
        parallel_steps =
          workflow.steps
          |> Map.values()
          |> Enum.filter(&(&1.group_id == pg.group_id and &1.group_type == :parallel_branch))

        branch_root_ids = root_branch_ids(pg)

        branch_roots =
          parallel_steps
          |> Enum.filter(&(&1.step_id in branch_root_ids))

        parent_ids =
          branch_roots
          |> Enum.flat_map(& &1.parent_ids)
          |> Enum.uniq()

        fan_out =
          for parent <- parent_ids, branch <- branch_roots do
            Edge.build(parent, branch.step_id, :fan_out)
          end

        fan_in =
          if is_binary(pg.merge_step_id) do
            pg.branch_terminal_step_ids
            |> Map.values()
            |> Enum.uniq()
            |> Enum.map(&Edge.build(&1, pg.merge_step_id, :fan_in))
          else
            []
          end

        fan_out ++ fan_in

      _ ->
        []
    end)
  end

  defp parallel_parent_ids(workflow, group_id) do
    parallel_steps =
      workflow.steps
      |> Map.values()
      |> Enum.filter(&(&1.group_id == group_id and &1.group_type == :parallel_branch))

    group =
      workflow.groups
      |> Map.values()
      |> Enum.find(fn
        %ParallelGroup{group_id: ^group_id} -> true
        _ -> false
      end)

    root_ids =
      case group do
        %ParallelGroup{} = pg -> root_branch_ids(pg)
        _ -> []
      end

    parallel_steps
    |> Enum.filter(&(&1.step_id in root_ids))
    |> Enum.flat_map(& &1.parent_ids)
    |> Enum.uniq()
  end

  defp root_branch_ids(%ParallelGroup{} = pg) do
    if pg.branch_root_step_ids != [] do
      pg.branch_root_step_ids
    else
      Map.keys(pg.branch_terminal_step_ids)
    end
  end

  defp atom_to_string(v) when is_atom(v), do: Atom.to_string(v)
  defp atom_to_string(v), do: v

  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso(_), do: nil
end
