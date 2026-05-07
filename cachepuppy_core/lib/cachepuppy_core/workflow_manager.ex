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
end
