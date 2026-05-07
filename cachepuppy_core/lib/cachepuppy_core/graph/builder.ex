defmodule CachePuppyCore.Graph.Builder do
  @moduledoc false

  alias CachePuppyCore.Graph
  alias CachePuppyCore.Graph.{Edge, Node}
  alias CachePuppyCore.Workflow
  alias CachePuppyCore.Workflow.{LoopGroup, ParallelGroup, Step}

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
    loop_iteration_map = loop_iteration_numbers(workflow)

    workflow.steps
    |> Map.values()
    |> Enum.map(fn step ->
      Node.from_step(step, Map.get(loop_iteration_map, step.step_id))
    end)
  end

  defp build_group_nodes(workflow) do
    workflow.groups
    |> Map.values()
    |> Enum.map(fn
      %ParallelGroup{} = group ->
        Node.from_parallel_group(group, parallel_parent_ids(workflow, group.group_id))

      %LoopGroup{} = group ->
        Node.from_loop_group(group, loop_parent_ids(workflow, group.group_id))
    end)
  end

  defp build_edges(workflow) do
    serial_edges = serial_edges(workflow)
    parallel_edges = parallel_edges(workflow)
    loop_edges = loop_edges(workflow)
    serial_edges ++ parallel_edges ++ loop_edges
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
        branch_steps =
          workflow.steps
          |> Map.values()
          |> Enum.filter(&(&1.group_id == pg.group_id and &1.group_type == :parallel_branch))

        parent_ids =
          branch_steps
          |> Enum.flat_map(& &1.parent_ids)
          |> Enum.uniq()

        fan_out =
          for parent <- parent_ids, branch <- branch_steps do
            Edge.build(parent, branch.step_id, :fan_out)
          end

        fan_in =
          if is_binary(pg.merge_step_id) do
            Enum.map(branch_steps, fn s -> Edge.build(s.step_id, pg.merge_step_id, :fan_in) end)
          else
            []
          end

        fan_out ++ fan_in

      _ ->
        []
    end)
  end

  defp loop_edges(workflow) do
    workflow.groups
    |> Map.values()
    |> Enum.flat_map(fn
      %LoopGroup{} = lg ->
        loop_steps =
          workflow.steps
          |> Map.values()
          |> Enum.filter(&(&1.group_id == lg.group_id and &1.group_type == :loop_iteration))
          |> Enum.sort_by(&(&1.inserted_at || ~U[1970-01-01 00:00:00Z]), DateTime)

        next_edges =
          loop_steps
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.map(fn [a, b] -> Edge.build(a.step_id, b.step_id, :loop_next) end)

        exit_edges =
          case List.last(loop_steps) do
            nil ->
              []

            last ->
              workflow.steps
              |> Map.values()
              |> Enum.filter(&(last.step_id in &1.parent_ids and &1.group_id != lg.group_id))
              |> Enum.map(&Edge.build(last.step_id, &1.step_id, :loop_exit))
          end

        next_edges ++ exit_edges

      _ ->
        []
    end)
  end

  defp loop_iteration_numbers(workflow) do
    workflow.groups
    |> Map.values()
    |> Enum.reduce(%{}, fn
      %LoopGroup{} = lg, acc ->
        lg.iterations
        |> Enum.with_index(1)
        |> Enum.reduce(acc, fn {iter, idx}, inner -> Map.put(inner, iter.step_id, idx) end)

      _, acc ->
        acc
    end)
  end

  defp parallel_parent_ids(workflow, group_id) do
    workflow.steps
    |> Map.values()
    |> Enum.filter(&(&1.group_id == group_id and &1.group_type == :parallel_branch))
    |> Enum.flat_map(& &1.parent_ids)
    |> Enum.uniq()
  end

  defp loop_parent_ids(workflow, group_id) do
    workflow.steps
    |> Map.values()
    |> Enum.filter(&(&1.group_id == group_id and &1.group_type == :loop_iteration))
    |> Enum.flat_map(& &1.parent_ids)
    |> Enum.uniq()
  end

  defp atom_to_string(v) when is_atom(v), do: Atom.to_string(v)
  defp atom_to_string(v), do: v

  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso(_), do: nil
end
