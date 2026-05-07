defmodule CachePuppyCore.WorkflowManager do
  @moduledoc false

  alias CachePuppyCore.WorkflowServer

  @spec ensure_started(String.t()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(workflow_id) when is_binary(workflow_id) do
    case Horde.Registry.lookup(CachePuppyCore.WorkflowRegistry, workflow_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        child_spec = {WorkflowServer, workflow_id: workflow_id}

        case Horde.DynamicSupervisor.start_child(CachePuppyCore.WorkflowSupervisor, child_spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
