defmodule CachePuppyCore.WorkflowManager do
  @moduledoc false

  alias CachePuppyCore.Workflow.WorkflowStore
  alias CachePuppyCore.WorkflowServer

  @spec ensure_started(String.t()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(workflow_id) when is_binary(workflow_id) do
    start_workflow(workflow_id, nil)
  end

  @spec start_workflow(String.t(), String.t() | nil) :: {:ok, pid()} | {:error, term()}
  def start_workflow(workflow_id, workflow_name) when is_binary(workflow_id) do
    case Horde.Registry.lookup(CachePuppyCore.WorkflowRegistry, workflow_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        child_spec = {WorkflowServer, workflow_id: workflow_id, workflow_name: workflow_name}

        case Horde.DynamicSupervisor.start_child(CachePuppyCore.WorkflowSupervisor, child_spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @spec start_workflow_confirmed(String.t(), String.t() | nil, keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start_workflow_confirmed(workflow_id, workflow_name, opts \\ [])
      when is_binary(workflow_id) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 1_000)
    interval_ms = Keyword.get(opts, :interval_ms, 25)

    with {:ok, _pid} <- start_workflow(workflow_id, workflow_name),
         :ok <- wait_until_visible_on_cluster(workflow_id, timeout_ms, interval_ms),
         {:ok, pid} <- lookup(workflow_id) do
      {:ok, pid}
    end
  end

  @spec lookup(String.t()) :: {:ok, pid()} | :not_found | {:error, term()}
  def lookup(workflow_id) when is_binary(workflow_id) do
    case Horde.Registry.lookup(CachePuppyCore.WorkflowRegistry, workflow_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case WorkflowStore.get(workflow_id) do
          {:ok, _workflow} -> start_workflow(workflow_id, nil)
          :not_found -> :not_found
        end
    end
  end

  defp wait_until_visible_on_cluster(workflow_id, timeout_ms, interval_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until_visible(workflow_id, deadline, interval_ms)
  end

  defp do_wait_until_visible(workflow_id, deadline, interval_ms) do
    if visible_on_all_nodes?(workflow_id) do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        {:error, :workflow_visibility_timeout}
      else
        Process.sleep(interval_ms)
        do_wait_until_visible(workflow_id, deadline, interval_ms)
      end
    end
  end

  defp visible_on_all_nodes?(workflow_id) do
    [node() | Node.list()]
    |> Enum.uniq()
    |> Enum.all?(&visible_on_node?(&1, workflow_id))
  end

  defp visible_on_node?(target_node, workflow_id) when target_node == node() do
    match?([_ | _], Horde.Registry.lookup(CachePuppyCore.WorkflowRegistry, workflow_id))
  end

  defp visible_on_node?(target_node, workflow_id) do
    try do
      case :erpc.call(
             target_node,
             Horde.Registry,
             :lookup,
             [CachePuppyCore.WorkflowRegistry, workflow_id],
             300
           ) do
        [_ | _] -> true
        _ -> false
      end
    catch
      _, _ -> false
    end
  end
end
