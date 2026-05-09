defmodule CachePuppyCoreWeb.StepController do
  use CachePuppyCoreWeb, :controller

  import Ecto.Changeset

  alias CachePuppyCore.{WorkflowManager, WorkflowServer}

  alias CachePuppyCoreWeb.Changesets.{
    ParallelMergeNowChangeset,
    ParallelChangeset,
    StepChangeset
  }

  alias CachePuppyCoreWeb.{ErrorJSON, WorkflowJSON}

  @resume_types %{step_id: :string, output: :map}
  @retry_types %{step_id: :string}

  def add_step(conn, %{"id" => workflow_id} = params) do
    invoking_step_id = invoking_step_id(params)

    with {:ok, _pid} <- lookup_workflow(workflow_id, conn),
         {:ok, step_params} <- StepChangeset.validate_params(params),
         {:ok, step} <-
           WorkflowServer.add_step(
             workflow_id,
             with_step_id(step_params),
             invoking_step_id: invoking_step_id
           ) do
      conn |> put_status(:created) |> json(WorkflowJSON.step_created(step))
    else
      {:conn, conn} -> conn
      {:error, %Ecto.Changeset{} = cs} -> bad_validation(conn, cs)
      other -> map_server_error(conn, workflow_id, other)
    end
  end

  def add_parallel(conn, %{"id" => workflow_id} = params) do
    invoking_step_id = invoking_step_id(params)

    with {:ok, _pid} <- lookup_workflow(workflow_id, conn),
         {:ok, %{steps: steps, merge_step: merge_step}} <-
           ParallelChangeset.validate_params(params) do
      steps_payload =
        Enum.map(steps, fn step -> step |> with_step_id() |> StepChangeset.to_step_params() end)

      merge_payload = merge_step |> with_step_id() |> StepChangeset.to_step_params()

      case WorkflowServer.add_parallel(
             workflow_id,
             steps_payload,
             merge_payload,
             invoking_step_id: invoking_step_id
           ) do
        {:ok, group_id, branch_steps, merge_created} ->
          conn
          |> put_status(:created)
          |> json(WorkflowJSON.parallel_created(group_id, branch_steps, merge_created))

        other ->
          map_server_error(conn, workflow_id, other)
      end
    else
      {:conn, conn} -> conn
      {:error, %Ecto.Changeset{} = cs} -> bad_validation(conn, cs)
    end
  end

  def merge_now(conn, %{"id" => workflow_id} = params) do
    with {:ok, _pid} <- lookup_workflow(workflow_id, conn),
         {:ok, attrs} <- ParallelMergeNowChangeset.validate_params(params) do
      case WorkflowServer.merge_now(workflow_id, attrs.merge_step_id) do
        {:ok, _group} ->
          conn |> put_status(:ok) |> json(%{"workflowId" => workflow_id, "status" => "ok"})

        other ->
          map_server_error(conn, workflow_id, other)
      end
    else
      {:conn, conn} -> conn
      {:error, %Ecto.Changeset{} = cs} -> bad_validation(conn, cs)
    end
  end

  def resume(conn, %{"id" => workflow_id} = params) do
    with {:ok, _pid} <- lookup_workflow(workflow_id, conn),
         {:ok, attrs} <- validate_resume(params),
         {:ok, _step} <- WorkflowServer.resume(workflow_id, attrs.step_id, attrs.output),
         {:ok, wf} <- WorkflowServer.get_state(workflow_id) do
      json(conn, WorkflowJSON.workflow_status(wf))
    else
      {:conn, conn} -> conn
      {:error, %Ecto.Changeset{} = cs} -> bad_validation(conn, cs)
      other -> map_server_error(conn, workflow_id, other)
    end
  end

  def retry_step(conn, %{"id" => workflow_id} = params) do
    with {:ok, _pid} <- lookup_workflow(workflow_id, conn),
         {:ok, attrs} <- validate_retry(params),
         {:ok, _step} <- WorkflowServer.retry_step(workflow_id, attrs.step_id),
         {:ok, wf} <- WorkflowServer.get_state(workflow_id) do
      json(conn, WorkflowJSON.workflow_status(wf))
    else
      {:conn, conn} -> conn
      {:error, %Ecto.Changeset{} = cs} -> bad_validation(conn, cs)
      other -> map_server_error(conn, workflow_id, other)
    end
  end

  def end_workflow(conn, %{"id" => workflow_id}) do
    with {:ok, _pid} <- lookup_workflow(workflow_id, conn),
         :ok <- WorkflowServer.end_workflow(workflow_id),
         {:ok, wf} <- WorkflowServer.get_state(workflow_id) do
      json(conn, WorkflowJSON.workflow_status(wf))
    else
      {:conn, conn} -> conn
      other -> map_server_error(conn, workflow_id, other)
    end
  end

  defp validate_resume(params) do
    cs =
      {%{}, @resume_types}
      |> cast(%{step_id: Map.get(params, "stepId"), output: Map.get(params, "output")}, [
        :step_id,
        :output
      ])
      |> validate_required([:step_id])
      |> put_output_default()

    if cs.valid?, do: {:ok, apply_changes(cs)}, else: {:error, cs}
  end

  defp put_output_default(cs) do
    if get_field(cs, :output) == nil, do: put_change(cs, :output, %{}), else: cs
  end

  defp validate_retry(params) do
    cs =
      {%{}, @retry_types}
      |> cast(%{step_id: Map.get(params, "stepId")}, [:step_id])
      |> validate_required([:step_id])

    if cs.valid?, do: {:ok, apply_changes(cs)}, else: {:error, cs}
  end

  defp with_step_id(attrs) do
    case Map.get(attrs, :step_id) do
      id when is_binary(id) and id != "" ->
        attrs

      _ ->
        Map.put(
          attrs,
          :step_id,
          "step_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
        )
    end
  end

  defp invoking_step_id(params) do
    case Map.get(params, "invokingStepId") do
      id when is_binary(id) and id != "" -> id
      _ -> nil
    end
  end

  defp lookup_workflow(workflow_id, conn) do
    case WorkflowManager.lookup(workflow_id) do
      {:ok, pid} ->
        {:ok, pid}

      :not_found ->
        {:conn, conn |> put_status(:not_found) |> json(ErrorJSON.workflow_not_found(workflow_id))}

      {:error, _reason} ->
        {:conn, conn |> put_status(:internal_server_error) |> json(ErrorJSON.internal_error())}
    end
  end

  defp bad_validation(conn, cs) do
    details = traverse_errors(cs, fn {msg, _opts} -> msg end)
    conn |> put_status(:bad_request) |> json(ErrorJSON.validation_failed(details))
  end

  defp map_server_error(conn, _workflow_id, {:error, :invalid_status}) do
    conn |> put_status(:conflict) |> json(ErrorJSON.workflow_already_completed())
  end

  defp map_server_error(conn, _workflow_id, {:error, :invalid_step}) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorJSON.validation_failed(%{"step" => ["invalid step payload"]}))
  end

  defp map_server_error(conn, _workflow_id, {:error, :invalid_invoking_step}) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorJSON.validation_failed(%{"invokingStepId" => ["invalid or unknown step id"]}))
  end

  defp map_server_error(conn, _workflow_id, {:error, :invalid_retry_state}) do
    conn
    |> put_status(:conflict)
    |> json(ErrorJSON.validation_failed(%{"workflow" => ["workflow is not in a failed state"]}))
  end

  defp map_server_error(conn, _workflow_id, {:error, :retry_step_not_failed}) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorJSON.validation_failed(%{"stepId" => ["step is not failed"]}))
  end

  defp map_server_error(conn, _workflow_id, {:error, :retry_step_still_running}) do
    conn
    |> put_status(:conflict)
    |> json(ErrorJSON.validation_failed(%{"stepId" => ["step is still running"]}))
  end

  defp map_server_error(conn, _workflow_id, {:error, :invalid_steps}) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorJSON.validation_failed(%{"steps" => ["invalid steps payload"]}))
  end

  defp map_server_error(conn, _workflow_id, {:error, :not_found}) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorJSON.validation_failed(%{"stepId" => ["step not found"]}))
  end

  defp map_server_error(conn, _workflow_id, {:error, :invalid_parallel_branch}) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorJSON.validation_failed(%{"branchId" => ["invalid parallel branch"]}))
  end

  defp map_server_error(conn, _workflow_id, {:error, :merge_already_armed}) do
    conn
    |> put_status(:conflict)
    |> json(ErrorJSON.validation_failed(%{"mergeStepId" => ["merge already armed"]}))
  end

  defp map_server_error(conn, _workflow_id, {:error, :parallel_merge_started}) do
    conn
    |> put_status(:conflict)
    |> json(ErrorJSON.validation_failed(%{"mergeStepId" => ["merge already started"]}))
  end

  defp map_server_error(conn, _workflow_id, _other) do
    conn |> put_status(:internal_server_error) |> json(ErrorJSON.internal_error())
  end
end
