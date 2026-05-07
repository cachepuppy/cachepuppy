defmodule CachePuppyCore.WorkflowServer do
  @moduledoc """
  GenServer owning one workflow execution's state.

  Registered under `Horde.Registry` as `{CachePuppyCore.WorkflowRegistry, workflow_id}`.
  Persists to ETS via `CachePuppyCore.Workflow.WorkflowStore` after each successful mutation.
  """

  use GenServer

  alias CachePuppyCore.Workflow
  alias CachePuppyCore.Workflow.{LoopGroup, LoopIteration, ParallelGroup, Step}
  alias CachePuppyCore.Workflow.WorkflowStore

  # --- Client ---

  def child_spec(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)

    %{
      id: {__MODULE__, workflow_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent
    }
  end

  def start_link(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    GenServer.start_link(__MODULE__, opts, name: via(workflow_id))
  end

  def add_step(workflow_id, step), do: GenServer.call(via(workflow_id), {:add_step, step})

  def add_parallel_steps(workflow_id, steps),
    do: GenServer.call(via(workflow_id), {:add_parallel_steps, steps})

  def add_merge_step(workflow_id, step),
    do: GenServer.call(via(workflow_id), {:add_merge_step, step})

  def add_loop(workflow_id, step, continue_if, max_iterations),
    do: GenServer.call(via(workflow_id), {:add_loop, step, continue_if, max_iterations})

  def resume(workflow_id, step_id, output),
    do: GenServer.call(via(workflow_id), {:resume, step_id, output})

  def execute_now(workflow_id, step),
    do: GenServer.call(via(workflow_id), {:execute_now, step})

  def end_workflow(workflow_id), do: GenServer.call(via(workflow_id), :end_workflow)

  def get_state(workflow_id), do: GenServer.call(via(workflow_id), :get_state)

  defp via(workflow_id),
    do: {:via, Horde.Registry, {CachePuppyCore.WorkflowRegistry, workflow_id}}

  # --- Server ---

  @impl true
  def init(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)

    workflow =
      case WorkflowStore.get(workflow_id) do
        {:ok, wf} -> wf
        :not_found -> Workflow.new(workflow_id)
      end

    {:ok, workflow}
  end

  @impl true
  def handle_call(:get_state, _from, workflow) do
    {:reply, {:ok, workflow}, workflow}
  end

  def handle_call(:end_workflow, _from, workflow) do
    if workflow.status in [:completed, :failed] do
      {:reply, {:error, :invalid_status}, workflow}
    else
      workflow =
        workflow
        |> Map.put(:status, :completed)
        |> touch()

      :ok = commit(workflow)
      {:reply, :ok, workflow}
    end
  end

  def handle_call({:add_step, step}, _from, workflow) do
    with :ok <- ensure_mutable(workflow),
         {:ok, step} <- to_step(step),
         :ok <- ensure_unique_step(workflow, step.step_id),
         {:ok, workflow} <- maybe_activate(workflow) do
      {step, workflow} = apply_serial_parents(step, workflow)
      step = %{step | inserted_at: step.inserted_at || DateTime.utc_now()}
      workflow = put_step(workflow, step)
      workflow = %{workflow | serial_tail_step_id: step.step_id}
      workflow = touch(workflow)
      :ok = commit(workflow)
      {:reply, {:ok, step}, workflow}
    else
      {:error, _} = err -> {:reply, err, workflow}
    end
  end

  def handle_call({:add_parallel_steps, steps}, _from, workflow) do
    with :ok <- ensure_mutable(workflow),
         {:ok, steps} <- normalize_steps_list(steps),
         :ok <- ensure_all_unique_steps(workflow, steps),
         false <- steps == [],
         {:ok, workflow} <- maybe_activate(workflow) do
      group_id = generate_id("pg")
      n = length(steps)

      {branch_steps, workflow} =
        steps
        |> Enum.with_index()
        |> Enum.map_reduce(workflow, fn {step, idx}, wf ->
          {step, wf} = apply_serial_parents(step, wf)
          step = %{step | group_id: group_id, branch_index: idx}
          step = %{step | inserted_at: step.inserted_at || DateTime.utc_now()}
          {step, put_step(wf, step)}
        end)

      group = %ParallelGroup{
        group_id: group_id,
        total_branches: n,
        completed_branches: 0,
        collected_outputs: [],
        merge_step_id: nil,
        status: :open
      }

      workflow =
        workflow
        |> put_group(group)
        |> Map.put(:open_parallel_group_id, group_id)
        |> touch()

      :ok = commit(workflow)
      {:reply, {:ok, group_id, branch_steps}, workflow}
    else
      true -> {:reply, {:error, :empty_parallel_branches}, workflow}
      {:error, _} = err -> {:reply, err, workflow}
    end
  end

  def handle_call({:add_merge_step, step}, _from, workflow) do
    with :ok <- ensure_mutable(workflow),
         gid when is_binary(gid) <- workflow.open_parallel_group_id,
         %ParallelGroup{status: :open} = pg <- Map.get(workflow.groups, gid),
         {:ok, step} <- to_step(step),
         :ok <- ensure_unique_step(workflow, step.step_id),
         {:ok, workflow} <- maybe_activate(workflow) do
      branch_ids = parallel_branch_step_ids(workflow, gid)
      step = apply_merge_parents(step, branch_ids)
      step = %{step | inserted_at: step.inserted_at || DateTime.utc_now()}
      workflow = put_step(workflow, step)

      pg = %{pg | merge_step_id: step.step_id, status: :waiting_for_merge_step}
      workflow = put_group(workflow, pg)

      workflow =
        workflow
        |> Map.put(:open_parallel_group_id, nil)
        |> Map.put(:serial_tail_step_id, step.step_id)
        |> touch()

      :ok = commit(workflow)
      {:reply, {:ok, step}, workflow}
    else
      nil -> {:reply, {:error, :no_open_parallel_group}, workflow}
      %ParallelGroup{} -> {:reply, {:error, :parallel_group_not_open}, workflow}
      {:error, _} = err -> {:reply, err, workflow}
    end
  end

  def handle_call({:add_loop, step, continue_if, max_iterations}, _from, workflow)
      when is_binary(continue_if) and is_integer(max_iterations) and max_iterations >= 0 do
    with :ok <- ensure_mutable(workflow),
         {:ok, step} <- to_step(step),
         :ok <- ensure_unique_step(workflow, step.step_id),
         {:ok, workflow} <- maybe_activate(workflow) do
      group_id = generate_id("lg")
      {step, workflow} = apply_serial_parents(step, workflow)
      step = %{step | group_id: group_id, inserted_at: step.inserted_at || DateTime.utc_now()}
      workflow = put_step(workflow, step)

      group = %LoopGroup{
        group_id: group_id,
        step_name: step.step_name,
        continue_if: continue_if,
        max_iterations: max_iterations,
        current_iteration: 0,
        iterations: [],
        status: :running
      }

      workflow =
        workflow
        |> put_group(group)
        |> Map.put(:serial_tail_step_id, step.step_id)
        |> touch()

      :ok = commit(workflow)
      {:reply, {:ok, group_id}, workflow}
    else
      {:error, _} = err -> {:reply, err, workflow}
    end
  end

  def handle_call({:add_loop, _, _, _}, _from, workflow) do
    {:reply, {:error, :invalid_loop_args}, workflow}
  end

  def handle_call({:resume, step_id, output}, _from, workflow) do
    with :ok <- ensure_mutable(workflow) do
      resume_step(workflow, step_id, output)
    else
      {:error, _} = err -> {:reply, err, workflow}
    end
  end

  def handle_call({:execute_now, step}, _from, workflow) do
    with :ok <- ensure_mutable(workflow),
         {:ok, step} <- to_step(step),
         :ok <- ensure_unique_step(workflow, step.step_id),
         {:ok, workflow} <- maybe_activate(workflow) do
      {step, workflow} = apply_serial_parents(step, workflow)
      now = DateTime.utc_now()

      out =
        case step.output do
          nil -> %{}
          other -> other
        end

      step = %{
        step
        | inserted_at: step.inserted_at || now,
          started_at: now,
          completed_at: now,
          status: :completed,
          output: out
      }

      workflow =
        workflow
        |> put_step(step)
        |> Map.put(:serial_tail_step_id, step.step_id)
        |> touch()

      :ok = commit(workflow)
      {:reply, {:ok, step}, workflow}
    else
      {:error, _} = err -> {:reply, err, workflow}
    end
  end

  defp resume_step(workflow, step_id, output) do
    case Map.get(workflow.steps, step_id) do
      nil ->
        {:reply, {:error, :not_found}, workflow}

      step ->
        now = DateTime.utc_now()

        step = %{
          step
          | status: :completed,
            output: output,
            completed_at: now
        }

        workflow = put_step(workflow, step)
        workflow = apply_parallel_resume(workflow, step)
        workflow = apply_loop_resume(workflow, step)
        workflow = touch(workflow)
        :ok = commit(workflow)
        {:reply, {:ok, step}, workflow}
    end
  end

  defp commit(%Workflow{id: id} = workflow) do
    WorkflowStore.put(id, workflow)
  end

  defp touch(%Workflow{} = workflow) do
    %{workflow | updated_at: DateTime.utc_now()}
  end

  defp ensure_mutable(%Workflow{status: s}) when s in [:completed, :failed] do
    {:error, :invalid_status}
  end

  defp ensure_mutable(%Workflow{}), do: :ok

  defp maybe_activate(%Workflow{status: :pending} = workflow) do
    {:ok, %{workflow | status: :running}}
  end

  defp maybe_activate(%Workflow{status: s} = workflow) when s in [:running, :waiting] do
    {:ok, workflow}
  end

  defp maybe_activate(%Workflow{}) do
    {:error, :invalid_status}
  end

  defp put_step(%Workflow{steps: steps} = workflow, %Step{} = step) do
    %{workflow | steps: Map.put(steps, step.step_id, step)}
  end

  defp put_group(%Workflow{groups: groups} = workflow, %{group_id: gid} = group) do
    %{workflow | groups: Map.put(groups, gid, group)}
  end

  defp apply_serial_parents(
         %Step{parent_ids: []} = step,
         %Workflow{serial_tail_step_id: tid} = workflow
       )
       when is_binary(tid) do
    {%{step | parent_ids: [tid]}, workflow}
  end

  defp apply_serial_parents(%Step{} = step, workflow) do
    {step, workflow}
  end

  defp apply_merge_parents(%Step{parent_ids: []} = step, branch_ids) do
    %{step | parent_ids: branch_ids}
  end

  defp apply_merge_parents(%Step{} = step, _branch_ids), do: step

  defp parallel_branch_step_ids(%Workflow{steps: steps}, group_id) do
    steps
    |> Map.values()
    |> Enum.filter(&(&1.group_id == group_id))
    |> Enum.map(& &1.step_id)
    |> Enum.sort()
  end

  defp apply_parallel_resume(workflow, %Step{group_id: nil}), do: workflow

  defp apply_parallel_resume(workflow, %Step{group_id: gid, step_id: sid, output: out}) do
    case Map.get(workflow.groups, gid) do
      %ParallelGroup{} = pg ->
        entry = %{step_id: sid, output: out}
        collected = pg.collected_outputs ++ [entry]

        pg = %{
          pg
          | completed_branches: pg.completed_branches + 1,
            collected_outputs: collected
        }

        put_group(workflow, pg)

      _ ->
        workflow
    end
  end

  defp apply_loop_resume(workflow, %Step{group_id: nil}), do: workflow

  defp apply_loop_resume(workflow, %Step{group_id: gid} = step) do
    case Map.get(workflow.groups, gid) do
      %LoopGroup{} = lg ->
        iter = %LoopIteration{
          step_id: step.step_id,
          input: step.input,
          output: step.output,
          status: :completed
        }

        iterations = lg.iterations ++ [iter]

        lg = %{
          lg
          | iterations: iterations,
            current_iteration: lg.current_iteration + 1
        }

        put_group(workflow, lg)

      _ ->
        workflow
    end
  end

  defp ensure_unique_step(%Workflow{steps: steps}, step_id) do
    if Map.has_key?(steps, step_id) do
      {:error, :duplicate_step}
    else
      :ok
    end
  end

  defp ensure_all_unique_steps(%Workflow{steps: steps}, new_steps) do
    ids = Enum.map(new_steps, & &1.step_id)

    cond do
      length(ids) != length(Enum.uniq(ids)) ->
        {:error, :duplicate_step}

      Enum.any?(ids, &Map.has_key?(steps, &1)) ->
        {:error, :duplicate_step}

      true ->
        :ok
    end
  end

  defp normalize_steps_list(steps) when is_list(steps) do
    results = Enum.map(steps, &to_step/1)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, s} -> s end)}
      err -> err
    end
  end

  defp normalize_steps_list(_), do: {:error, :invalid_steps}

  defp to_step(%Step{} = step), do: {:ok, step}

  defp to_step(m) when is_map(m) do
    try do
      step = struct_from_map(Step, m)
      validate_required_step(step)
    rescue
      ArgumentError ->
        {:error, :invalid_step}
    end
  end

  defp to_step(_), do: {:error, :invalid_step}

  defp struct_from_map(mod, m) do
    base = struct(mod)

    Enum.reduce(Map.to_list(m), base, fn
      {k, v}, acc when is_atom(k) ->
        if Map.has_key?(acc, k), do: Map.put(acc, k, v), else: acc

      {k, v}, acc when is_binary(k) ->
        case step_field_atom(k) do
          nil -> acc
          atom -> Map.put(acc, atom, v)
        end
    end)
  end

  defp step_field_atom("step_id"), do: :step_id
  defp step_field_atom("step_name"), do: :step_name
  defp step_field_atom("url"), do: :url
  defp step_field_atom("method"), do: :method
  defp step_field_atom("data"), do: :data
  defp step_field_atom("status"), do: :status
  defp step_field_atom("success_codes"), do: :success_codes
  defp step_field_atom("max_retries"), do: :max_retries
  defp step_field_atom("retry_count"), do: :retry_count
  defp step_field_atom("input"), do: :input
  defp step_field_atom("output"), do: :output
  defp step_field_atom("parent_ids"), do: :parent_ids
  defp step_field_atom("group_id"), do: :group_id
  defp step_field_atom("branch_index"), do: :branch_index
  defp step_field_atom("inserted_at"), do: :inserted_at
  defp step_field_atom("started_at"), do: :started_at
  defp step_field_atom("completed_at"), do: :completed_at
  defp step_field_atom(_), do: nil

  defp validate_required_step(%Step{step_id: id, step_name: n, url: u} = step)
       when is_binary(id) and is_binary(n) and is_binary(u) do
    parent_ids =
      case step.parent_ids do
        nil -> []
        list when is_list(list) -> list
        _ -> :bad
      end

    if parent_ids == :bad do
      {:error, :invalid_step}
    else
      {:ok, %{step | parent_ids: parent_ids}}
    end
  end

  defp validate_required_step(_), do: {:error, :invalid_step}

  defp generate_id(prefix) do
    prefix <> "-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
