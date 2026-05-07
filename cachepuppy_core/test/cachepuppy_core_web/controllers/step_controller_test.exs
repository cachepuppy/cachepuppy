defmodule CachePuppyCoreWeb.StepControllerTest do
  use CachePuppyCoreWeb.ConnCase, async: false

  alias CachePuppyCore.Workflow.WorkflowStore

  defmodule ExecutorStub do
    @moduledoc false
    def execute(step, _workflow_id, _opts) do
      {:ok, %{status_code: 200, body: %{"ok" => true}, step: %{step | retry_count: 0}}}
    end
  end

  setup do
    old_mod = Application.get_env(:cachepuppy_core, :workflow_step_executor_module)
    Application.put_env(:cachepuppy_core, :workflow_step_executor_module, ExecutorStub)

    on_exit(fn ->
      if old_mod do
        Application.put_env(:cachepuppy_core, :workflow_step_executor_module, old_mod)
      else
        Application.delete_env(:cachepuppy_core, :workflow_step_executor_module)
      end
    end)

    :ok
  end

  test "POST /api/workflows/:id/steps adds a serial step", %{conn: conn} do
    wf = post(conn, "/api/workflows", %{"name" => "wf"}) |> json_response(201)
    id = wf["workflowId"]

    payload = %{
      "stepName" => "extract",
      "url" => "https://myapp.com/extract",
      "method" => "post",
      "data" => %{"paragraph" => "..."},
      "successCodes" => [200],
      "maxRetries" => 3
    }

    conn = post(build_conn(), "/api/workflows/#{id}/steps", payload)
    body = json_response(conn, 201)
    assert body["stepId"]
    assert body["stepName"] == "extract"

    WorkflowStore.delete(id)
  end

  test "POST /api/workflows/:id/steps validates payload", %{conn: conn} do
    wf = post(conn, "/api/workflows", %{"name" => "wf"}) |> json_response(201)
    id = wf["workflowId"]

    conn = post(build_conn(), "/api/workflows/#{id}/steps", %{"stepName" => "x"})
    body = json_response(conn, 400)
    assert body["error"] == "validation_failed"

    WorkflowStore.delete(id)
  end

  test "POST /api/workflows/:id/resume returns conflict when workflow already completed", %{
    conn: conn
  } do
    wf = post(conn, "/api/workflows", %{"name" => "wf"}) |> json_response(201)
    id = wf["workflowId"]

    step =
      post(build_conn(), "/api/workflows/#{id}/steps", %{
        "stepName" => "extract",
        "url" => "https://myapp.com/extract",
        "method" => "post"
      })
      |> json_response(201)

    conn =
      post(build_conn(), "/api/workflows/#{id}/resume", %{
        "stepId" => step["stepId"],
        "output" => %{}
      })

    body = json_response(conn, 409)
    assert body["error"] == "workflow_already_completed"

    WorkflowStore.delete(id)
  end

  test "POST /api/workflows/:id/end marks completed", %{conn: conn} do
    wf = post(conn, "/api/workflows", %{"name" => "wf"}) |> json_response(201)
    id = wf["workflowId"]

    conn = post(build_conn(), "/api/workflows/#{id}/end", %{})
    body = json_response(conn, 200)
    assert body["workflowId"] == id
    assert body["status"] == "completed"

    WorkflowStore.delete(id)
  end

  test "returns 404 for unknown workflow id", %{conn: conn} do
    conn = post(conn, "/api/workflows/unknown/steps", %{})
    body = json_response(conn, 404)
    assert body["error"] == "workflow_not_found"
  end
end
