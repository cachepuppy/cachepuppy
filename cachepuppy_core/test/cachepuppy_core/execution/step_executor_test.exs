defmodule CachePuppyCore.Execution.StepExecutorTest do
  use ExUnit.Case, async: true

  alias CachePuppyCore.Execution.StepExecutor
  alias CachePuppyCore.Workflow.Step

  defmodule SeqHttp do
    @moduledoc false
    def post_step(_url, _body, _headers, opts) do
      agent = Keyword.fetch!(opts, :stub_agent)

      Agent.get_and_update(agent, fn
        %{left: [h | t]} -> {h, %{left: t}}
        %{left: []} -> raise "SeqHttp: no stub responses left"
      end)
    end
  end

  defp step(attrs) when is_list(attrs) do
    struct(
      %Step{
        step_id: "s1",
        step_name: "test_step",
        url: "http://example.test/step",
        data: %{"k" => "v"},
        success_codes: [200],
        max_retries: 0
      },
      attrs
    )
  end

  defp stub_agent!(responses) do
    start_supervised!({Agent, fn -> %{left: responses} end})
  end

  test "success on first try returns body and zero retry_count" do
    agent = stub_agent!([{:ok, %{status: 200, body: %{"ok" => true}}}])

    assert {:ok, %{status_code: 200, body: %{"ok" => true}, step: st}} =
             StepExecutor.execute(step(max_retries: 0), "wf-a",
               http_client: SeqHttp,
               http_client_opts: [stub_agent: agent],
               max_retries: 0,
               skip_sleep: true
             )

    assert st.retry_count == 0
  end

  test "retries on bad status then succeeds" do
    agent =
      stub_agent!([
        {:ok, %{status: 500, body: "no"}},
        {:ok, %{status: 200, body: %{"fixed" => true}}}
      ])

    assert {:ok, %{status_code: 200, body: %{"fixed" => true}, step: st}} =
             StepExecutor.execute(step(success_codes: [200], max_retries: 0), "wf-b",
               http_client: SeqHttp,
               http_client_opts: [stub_agent: agent],
               max_retries: 2,
               skip_sleep: true
             )

    assert st.retry_count == 1
  end

  test "max_retries_exceeded returns last_status_code" do
    agent =
      stub_agent!([
        {:ok, %{status: 500, body: "a"}},
        {:ok, %{status: 500, body: "b"}},
        {:ok, %{status: 500, body: "c"}},
        {:ok, %{status: 500, body: "d"}}
      ])

    assert {:error,
            %{
              reason: :max_retries_exceeded,
              attempts: 4,
              last_status_code: 500,
              step: st
            }} =
             StepExecutor.execute(step(success_codes: [200], max_retries: 0), "wf-c",
               http_client: SeqHttp,
               http_client_opts: [stub_agent: agent],
               max_retries: 3,
               skip_sleep: true
             )

    assert st.retry_count == 4
  end

  test "timeout error after retries" do
    agent =
      stub_agent!([
        {:error, {:timeout, "timed out"}},
        {:error, {:timeout, "timed out"}},
        {:error, {:timeout, "timed out"}},
        {:error, {:timeout, "timed out"}}
      ])

    assert {:error, %{reason: :timeout, attempts: 4, step: _}} =
             StepExecutor.execute(step(max_retries: 0), "wf-d",
               http_client: SeqHttp,
               http_client_opts: [stub_agent: agent],
               max_retries: 3,
               skip_sleep: true
             )
  end

  test "connection_error" do
    agent =
      stub_agent!([
        {:error, {:connection_error, "econnrefused"}}
      ])

    assert {:error,
            %{
              reason: :connection_error,
              attempts: 1,
              message: "econnrefused",
              step: _
            }} =
             StepExecutor.execute(step(max_retries: 0), "wf-e",
               http_client: SeqHttp,
               http_client_opts: [stub_agent: agent],
               max_retries: 0,
               skip_sleep: true
             )
  end

  defmodule CaptureHttp do
    @moduledoc false
    def post_step(_url, body, _headers, opts) do
      agent = Keyword.fetch!(opts, :stub_agent)
      _ = Agent.update(agent, fn s -> %{s | bodies: [body | s.bodies]} end)
      {:ok, %{status: 200, body: %{}}}
    end
  end

  test "merge_data appears in JSON body sent to HTTP client" do
    agent = start_supervised!({Agent, fn -> %{bodies: []} end})

    assert {:ok, _} =
             StepExecutor.execute(step(max_retries: 0), "wf-f",
               http_client: CaptureHttp,
               http_client_opts: [stub_agent: agent],
               max_retries: 0,
               merge_data: [%{"x" => 1}],
               skip_sleep: true
             )

    [body | _] = Agent.get(agent, & &1.bodies)
    assert body["input"]["mergeData"] == [%{"x" => 1}]
    assert body["input"]["workflowId"] == "wf-f"
  end
end
