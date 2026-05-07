defmodule CachePuppyCore.Workflow.WorkflowStore do
  @moduledoc """
  Node-local ETS snapshots for workflow state.

  Each successful mutation in `CachePuppyCore.WorkflowServer` is written here so the
  GenServer can reload after a crash on the same node. ETS is not replicated
  across the cluster; loss of the node loses these snapshots unless a durable
  backend is added later.
  """

  alias CachePuppyCore.Workflow

  @default_table :cachepuppy_workflow_snapshots

  @spec table() :: atom()
  def table do
    Application.get_env(:cachepuppy_core, :workflow_store_table, @default_table)
  end

  @spec ensure_table() :: :ok
  def ensure_table do
    t = table()

    case :ets.whereis(t) do
      :undefined ->
        :ets.new(t, [:named_table, :public, :set, read_concurrency: true])

      _tid ->
        :ok
    end

    :ok
  end

  @spec put(String.t(), Workflow.t()) :: :ok
  def put(workflow_id, %Workflow{} = workflow) when is_binary(workflow_id) do
    _ = ensure_table()
    true = :ets.insert(table(), {workflow_id, workflow})
    :ok
  end

  @spec get(String.t()) :: {:ok, Workflow.t()} | :not_found
  def get(workflow_id) when is_binary(workflow_id) do
    case :ets.whereis(table()) do
      :undefined ->
        :not_found

      _tid ->
        case :ets.lookup(table(), workflow_id) do
          [{^workflow_id, %Workflow{} = workflow}] -> {:ok, workflow}
          [] -> :not_found
        end
    end
  end

  @spec delete(String.t()) :: :ok
  def delete(workflow_id) when is_binary(workflow_id) do
    case :ets.whereis(table()) do
      :undefined ->
        :ok

      _tid ->
        _ = :ets.delete(table(), workflow_id)
        :ok
    end
  end
end
