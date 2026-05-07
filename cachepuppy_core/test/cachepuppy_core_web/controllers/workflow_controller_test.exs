defmodule CachePuppyCoreWeb.WorkflowControllerTest do
  use CachePuppyCoreWeb.ConnCase, async: false

  alias CachePuppyCore.Workflow.WorkflowStore

  test "POST /api/workflows creates workflow", %{conn: conn} do
    conn = post(conn, "/api/workflows", %{"name" => "extract_research_compile"})
    body = json_response(conn, 201)

    assert body["workflowId"]
    assert body["name"] == "extract_research_compile"
    assert body["status"] in ["pending", "running"]

    WorkflowStore.delete(body["workflowId"])
  end

  test "POST /api/workflows validates name", %{conn: conn} do
    conn = post(conn, "/api/workflows", %{})
    body = json_response(conn, 400)
    assert body["error"] == "validation_failed"
    assert is_map(body["details"])
  end

  test "GET /api/workflows/:id returns 404 when missing", %{conn: conn} do
    conn = get(conn, "/api/workflows/does-not-exist")
    body = json_response(conn, 404)
    assert body["error"] == "workflow_not_found"
  end
end
