defmodule CachePuppyCore.Execution.PayloadTest do
  use ExUnit.Case, async: true

  alias CachePuppyCore.Execution.Payload
  alias CachePuppyCore.Workflow.Step

  test "build_body omits mergeData by default" do
    step = %Step{step_id: "1", step_name: "s", url: "http://x", data: %{"a" => 1}}
    body = Payload.build_body("wf-1", step)

    assert body == %{
             "input" => %{
               "workflowId" => "wf-1",
               "data" => %{"a" => 1}
             }
           }

    assert body |> Jason.encode!() =~ "workflowId"
    refute body |> Jason.encode!() =~ "mergeData"
  end

  test "build_body includes mergeData when merge list is provided" do
    step = %Step{step_id: "1", step_name: "merge", url: "http://x", data: %{}}
    md = [%{"out" => 1}, %{"out" => 2}]
    body = Payload.build_body("wf-1", step, md)

    assert body["input"]["mergeData"] == md
  end

  test "build_body includes empty mergeData when passed empty list" do
    step = %Step{step_id: "1", step_name: "merge", url: "http://x", data: nil}
    body = Payload.build_body("wf-1", step, [])

    assert body["input"]["mergeData"] == []
  end

  test "build_headers uses CachePuppy header names" do
    step = %Step{step_id: "1", step_name: "extract", url: "http://x"}

    headers = Payload.build_headers("wf-9", step) |> Map.new()

    assert headers["content-type"] == "application/json"
    assert headers["x-cachepuppy-step"] == "extract"
    assert headers["x-cachepuppy-workflow"] == "wf-9"
  end
end
