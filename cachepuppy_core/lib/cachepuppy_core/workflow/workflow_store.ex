defmodule CachePuppyCore.Workflow.WorkflowStore do
  @moduledoc """
  Distributed workflow snapshots backed by the cache persistence layer.

  Each successful mutation in `CachePuppyCore.WorkflowServer` is written to the
  shared cache persistence layer so lookups can resolve from any node in a
  cluster without relying on node-local ETS affinity.
  """

  alias CachePuppyCore.Persistence.CacheRouter
  alias CachePuppyCore.Workflow

  @table "workflow_snapshots"

  @spec table() :: String.t()
  def table, do: @table

  @spec ensure_table() :: :ok
  def ensure_table, do: :ok

  @spec put(String.t(), Workflow.t()) :: :ok
  def put(workflow_id, %Workflow{} = workflow) when is_binary(workflow_id) do
    case CacheRouter.setdata(table(), workflow_id, workflow) do
      {:ok, _} -> :ok
      {:error, reason} -> raise "workflow_store_put_failed: #{inspect(reason)}"
    end
  end

  @spec get(String.t()) :: {:ok, Workflow.t()} | :not_found
  def get(workflow_id) when is_binary(workflow_id) do
    case CacheRouter.getdata(table(), workflow_id) do
      {:ok, %Workflow{} = workflow} ->
        {:ok, workflow}

      {:ok, nil} ->
        :not_found

      {:ok, _other} ->
        :not_found

      {:error, _reason} ->
        :not_found
    end
  end

  @spec delete(String.t()) :: :ok
  def delete(workflow_id) when is_binary(workflow_id) do
    case CacheRouter.deldata(table(), workflow_id) do
      {:ok, _deleted?} -> :ok
      {:error, _reason} -> :ok
    end
  end
end
