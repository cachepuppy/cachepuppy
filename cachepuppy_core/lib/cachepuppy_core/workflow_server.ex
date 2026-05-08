defmodule CachePuppyCore.WorkflowServer do
  @moduledoc """
  GenServer owning one workflow execution's state.
  """

  use GenServer

  alias CachePuppyCore.Execution.StepExecutor
  alias CachePuppyCore.Graph.Broadcaster
  alias CachePuppyCore.Orchestrator
  alias CachePuppyCore.Workflow
  alias CachePuppyCore.Workflow.{LoopGroup, ParallelGroup, Step}
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

  def add_parallel(workflow_id, steps, merge_step),
    do: GenServer.call(via(workflow_id), {:add_parallel, steps, merge_step})

  def close_parallel_branch(workflow_id, branch_id, terminal_step_id),
    do: GenServer.call(via(workflow_id), {:close_parallel_branch, branch_id, terminal_step_id})

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
    workflow_name = Keyword.get(opts, :workflow_name)

    workflow =
      case WorkflowStore.get(workflow_id) do
        {:ok, wf} -> wf
        :not_found -> Workflow.new(workflow_id, workflow_name)
      end

    {:ok, workflow, {:continue, :advance}}
  end

  @impl true
  def handle_continue(:advance, workflow) do
    workflow = advance_and_enqueue(workflow)
    :ok = commit(workflow)
    :ok = maybe_broadcast_graph(workflow)
    {:noreply, workflow}
  end

  @impl true
  def handle_call(:get_state, _from, workflow), do: {:reply, {:ok, workflow}, workflow}

  def handle_call(:end_workflow, _from, workflow) do
    if workflow.status in [:completed, :failed] do
      {:reply, {:error, :invalid_status}, workflow}
    else
      workflow =
        workflow
        |> Map.put(:status, :completed)
        |> touch()

      workflow = advance_and_enqueue(workflow)
      :ok = commit(workflow)
      :ok = maybe_broadcast_graph(workflow)
      {:reply, :ok, workflow}
    end
  end

  def handle_call({:add_step, step}, _from, workflow) do
    with :ok <- ensure_mutable(workflow),
         {:ok, step} <- to_step(step),
         :ok <- ensure_unique_step(workflow, step.step_id),
         {:ok, workflow} <- maybe_activate(workflow) do
      {step, workflow} = apply_serial_parents(step, workflow)
      with :ok <- validate_branch_addition_allowed(workflow, step) do
      step = %{step | inserted_at: step.inserted_at || DateTime.utc_now()}
      workflow = put_step(workflow, step)
      workflow = %{workflow | serial_tail_step_id: step.step_id}
      workflow = touch(workflow) |> advance_and_enqueue()
      :ok = commit(workflow)
      :ok = maybe_broadcast_graph(workflow)
      {:reply, {:ok, step}, workflow}
      else
        {:error, _} = err -> {:reply, err, workflow}
      end
    else
      {:error, _} = err -> {:reply, err, workflow}
    end
  end

  def handle_call({:add_parallel, steps, merge_step}, _from, workflow) do
    with :ok <- ensure_mutable(workflow),
         {:ok, steps} <- normalize_steps_list(steps),
         {:ok, merge_step} <- to_step(merge_step),
         :ok <- ensure_all_unique_steps(workflow, steps),
         :ok <- ensure_unique_step(workflow, merge_step.step_id),
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
          step = %{step | group_type: :parallel_branch}
          {step, put_step(wf, step)}
        end)

      branch_ids = Enum.map(branch_steps, & &1.step_id)

      merge_step =
        merge_step
        |> apply_merge_parents(branch_ids)
        |> Map.put(:inserted_at, merge_step.inserted_at || DateTime.utc_now())
        |> Map.put(:group_type, :parallel_merge)
        |> Map.put(:group_id, group_id)

      workflow = put_step(workflow, merge_step)

      group = %ParallelGroup{
        group_id: group_id,
        total_branches: n,
        merge_step_id: merge_step.step_id,
        branch_terminal_step_ids: Map.new(branch_ids, fn sid -> {sid, sid} end),
        branch_statuses: Map.new(branch_ids, fn sid -> {sid, :open} end),
        status: :open
      }

      workflow =
        workflow
        |> put_group(group)
        |> Map.put(:open_parallel_group_id, nil)
        |> Map.put(:serial_tail_step_id, merge_step.step_id)
        |> touch()

      workflow = advance_and_enqueue(workflow)
      :ok = commit(workflow)
      :ok = maybe_broadcast_graph(workflow)
      {:reply, {:ok, group_id, branch_steps, merge_step}, workflow}
    else
      true -> {:reply, {:error, :empty_parallel_branches}, workflow}
      {:error, _} = err -> {:reply, err, workflow}
    end
  end

  def handle_call({:close_parallel_branch, branch_id, terminal_step_id}, _from, workflow) do
    with :ok <- ensure_mutable(workflow),
         {:ok, workflow} <- maybe_activate(workflow),
         %Step{} = branch_root <- Map.get(workflow.steps, branch_id),
         true <- branch_root.group_type == :parallel_branch,
         %ParallelGroup{} = pg <- Map.get(workflow.groups, branch_root.group_id),
         true <- Map.has_key?(pg.branch_statuses, branch_id),
         :ok <- validate_terminal_step(workflow, branch_root.group_id, terminal_step_id) do
      pg =
        pg
        |> put_in([Access.key(:branch_statuses), branch_id], :closed)
        |> put_in([Access.key(:branch_terminal_step_ids), branch_id], terminal_step_id)

      merge_step = Map.fetch!(workflow.steps, pg.merge_step_id)
      merge_step = %{merge_step | parent_ids: pg.branch_terminal_step_ids |> Map.values() |> Enum.sort()}

      workflow =
        workflow
        |> put_step(merge_step)
        |> put_group(pg)
        |> touch()

      workflow = advance_and_enqueue(workflow)
      :ok = commit(workflow)
      :ok = maybe_broadcast_graph(workflow)
      {:reply, {:ok, pg}, workflow}
    else
      nil -> {:reply, {:error, :not_found}, workflow}
      false -> {:reply, {:error, :invalid_parallel_branch}, workflow}
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

      step = %{
        step
        | group_id: group_id,
          group_type: :loop_iteration,
          inserted_at: step.inserted_at || DateTime.utc_now()
      }

      workflow = put_step(workflow, step)

      group = %LoopGroup{
        group_id: group_id,
        step_name: step.step_name,
        continue_if: continue_if,
        max_iterations: max_iterations,
        current_iteration: 0,
        iterations: [],
        template_step_id: step.step_id,
        status: :running
      }

      workflow =
        workflow |> put_group(group) |> Map.put(:serial_tail_step_id, step.step_id) |> touch()

      workflow = advance_and_enqueue(workflow)
      :ok = commit(workflow)
      :ok = maybe_broadcast_graph(workflow)
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

      step = %{step | inserted_at: step.inserted_at || now, started_at: now}
      exec_opts = [merge_data: nil]
      result = step_executor_module().execute(step, workflow.id, execution_opts(exec_opts))

      {workflow, reply} =
        case result do
          {:ok, %{body: body, step: executed}} ->
            done = %{
              step
              | status: :completed,
                retry_count: executed.retry_count,
                output: body,
                completed_at: DateTime.utc_now()
            }

            wf =
              workflow
              |> put_step(done)
              |> Map.put(:serial_tail_step_id, step.step_id)
              |> touch()

            {wf, {:ok, done}}

          {:error, reason} ->
            failed = %{
              step
              | status: :failed,
                execution_error: reason,
                completed_at: DateTime.utc_now()
            }

            wf =
              workflow
              |> put_step(failed)
              |> Map.put(:serial_tail_step_id, step.step_id)
              |> touch()

            {wf, {:error, reason}}
        end

      :ok = commit(workflow)
      :ok = maybe_broadcast_graph(workflow)
      {:reply, reply, workflow}
    else
      {:error, _} = err -> {:reply, err, workflow}
    end
  end

  @impl true
  def handle_cast({:execution_result, step_id, result}, workflow) do
    {workflow, actions} = Orchestrator.on_step_result(workflow, step_id, result)
    workflow = enqueue_orchestration(workflow, actions)
    :ok = commit(workflow)
    :ok = maybe_broadcast_graph(workflow)
    {:noreply, workflow}
  end

  defp resume_step(workflow, step_id, output) do
    case Map.get(workflow.steps, step_id) do
      nil ->
        {:reply, {:error, :not_found}, workflow}

      step ->
        result = {:ok, %{status_code: 200, body: output, step: step}}
        {workflow, actions} = Orchestrator.on_step_result(workflow, step_id, result)
        workflow = enqueue_orchestration(workflow, actions)
        :ok = commit(workflow)
        :ok = maybe_broadcast_graph(workflow)
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

  defp apply_serial_parents(%Step{parent_ids: parent_ids} = step, %Workflow{} = workflow)
       when is_list(parent_ids) and parent_ids != [] do
    parent_steps =
      parent_ids
      |> Enum.map(&Map.get(workflow.steps, &1))
      |> Enum.reject(&is_nil/1)

    case parent_steps do
      [] ->
        {step, workflow}

      [first | rest] ->
        same_group? = Enum.all?(rest, &(&1.group_id == first.group_id))
        same_branch? = Enum.all?(rest, &(&1.branch_index == first.branch_index))

        if same_group? and
             is_binary(first.group_id) and
             same_branch? and
             first.group_type == :parallel_branch and
             is_integer(first.branch_index) do
          {%{step | group_id: first.group_id, group_type: :parallel_branch, branch_index: first.branch_index}, workflow}
        else
          {step, workflow}
        end
    end
  end

  defp apply_serial_parents(%Step{} = step, workflow) do
    {step, workflow}
  end

  defp apply_merge_parents(%Step{parent_ids: []} = step, branch_ids) do
    %{step | parent_ids: branch_ids}
  end

  defp apply_merge_parents(%Step{} = step, _branch_ids), do: step

  defp validate_terminal_step(%Workflow{steps: steps}, group_id, terminal_step_id) do
    case Map.get(steps, terminal_step_id) do
      %Step{group_id: ^group_id, group_type: :parallel_branch} -> :ok
      %Step{} -> {:error, :invalid_terminal_step}
      nil -> {:error, :not_found}
    end
  end

  defp validate_branch_addition_allowed(%Workflow{groups: _groups}, %Step{group_id: nil}), do: :ok

  defp validate_branch_addition_allowed(
         %Workflow{groups: groups, steps: steps},
         %Step{group_id: group_id, group_type: :parallel_branch, branch_index: branch_index}
       ) do
    case Map.get(groups, group_id) do
      %ParallelGroup{} = pg ->
        branch_root_id =
          pg.branch_terminal_step_ids
          |> Enum.find_value(fn {root_id, _terminal_id} ->
            if pg.branch_statuses[root_id] == :open and
                 root_branch_index(steps, root_id) == branch_index do
              root_id
            else
              nil
            end
          end)

        if branch_root_id, do: :ok, else: {:error, :parallel_branch_closed}

      _ ->
        :ok
    end
  end

  defp validate_branch_addition_allowed(_workflow, _step), do: :ok

  defp root_branch_index(steps, root_id) do
    case Map.get(steps, root_id) do
      %Step{} = step -> step.branch_index
      _ -> nil
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
  defp step_field_atom("group_type"), do: :group_type
  defp step_field_atom("parent_group_id"), do: :parent_group_id
  defp step_field_atom("execution_error"), do: :execution_error
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

  defp advance_and_enqueue(workflow) do
    {workflow, actions} = Orchestrator.advance(workflow)
    enqueue_orchestration(workflow, actions)
  end

  defp enqueue_orchestration(workflow, actions) do
    Enum.reduce(actions, workflow, fn {:execute_step, step, opts}, acc ->
      acc = Orchestrator.mark_step_running(acc, step.step_id)
      run_step_async(Map.fetch!(acc.steps, step.step_id), acc.id, opts)
      acc
    end)
  end

  defp run_step_async(step, workflow_id, opts) do
    _ =
      Task.start(fn ->
        result = step_executor_module().execute(step, workflow_id, execution_opts(opts))
        GenServer.cast(via(workflow_id), {:execution_result, step.step_id, result})
      end)

    :ok
  end

  defp step_executor_module do
    Application.get_env(:cachepuppy_core, :workflow_step_executor_module, StepExecutor)
  end

  defp execution_opts(opts) do
    defaults = Application.get_env(:cachepuppy_core, :workflow_step_executor_opts, [])
    Keyword.merge(defaults, opts)
  end

  defp maybe_broadcast_graph(%Workflow{id: workflow_id}) do
    Broadcaster.broadcast(workflow_id)
  end
end
