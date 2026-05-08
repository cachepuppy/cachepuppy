defmodule CachePuppyCoreWeb.WorkflowController do
  use CachePuppyCoreWeb, :controller

  import Ecto.Changeset

  alias CachePuppyCore.{WorkflowManager, WorkflowServer}
  alias CachePuppyCoreWeb.{ErrorJSON, WorkflowJSON}

  @create_types %{name: :string}

  def create(conn, params) when is_map(params) do
    case validate_create(params) do
      {:ok, attrs} ->
        workflow_id = "wf_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
        name = attrs.name

        case WorkflowManager.start_workflow_confirmed(workflow_id, name) do
          {:ok, _pid} ->
            conn
            |> put_status(:created)
            |> json(%{
              "workflowId" => workflow_id,
              "name" => name,
              "status" => "pending"
            })

          {:error, :workflow_visibility_timeout} ->
            conn
            |> put_status(:service_unavailable)
            |> json(%{"error" => "workflow_unavailable", "message" => "Workflow did not become visible in time"})

          {:error, _reason} ->
            conn |> put_status(:internal_server_error) |> json(ErrorJSON.internal_error())
        end

      {:error, details} ->
        conn |> put_status(:bad_request) |> json(ErrorJSON.validation_failed(details))
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorJSON.validation_failed(%{"name" => ["can't be blank"]}))
  end

  def show(conn, %{"id" => workflow_id}) when is_binary(workflow_id) do
    case WorkflowManager.lookup(workflow_id) do
      {:ok, _pid} ->
        case WorkflowServer.get_state(workflow_id) do
          {:ok, workflow} ->
            json(conn, WorkflowJSON.workflow_state(workflow))

          _ ->
            conn |> put_status(:internal_server_error) |> json(ErrorJSON.internal_error())
        end

      :not_found ->
        conn |> put_status(:not_found) |> json(ErrorJSON.workflow_not_found(workflow_id))

      {:error, _reason} ->
        conn |> put_status(:internal_server_error) |> json(ErrorJSON.internal_error())
    end
  end

  def show(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorJSON.validation_failed(%{"id" => ["is invalid"]}))
  end

  defp validate_create(params) do
    cs =
      {%{}, @create_types}
      |> cast(%{name: Map.get(params, "name")}, [:name])
      |> validate_required([:name])
      |> validate_length(:name, min: 1, max: 200)

    if cs.valid? do
      {:ok, apply_changes(cs)}
    else
      {:error, traverse_errors(cs, fn {msg, _opts} -> msg end)}
    end
  end

end
