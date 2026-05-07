defmodule CachePuppy.Test.E2E.CachePuppyHTTP do
  @moduledoc false

  @spec create_workflow(String.t(), String.t()) :: map()
  def create_workflow(api_base, name) do
    post_json!(api_base <> "/api/workflows", %{"name" => name}, 201)
  end

  @spec get_workflow(String.t(), String.t()) :: map()
  def get_workflow(api_base, workflow_id) do
    get_json!(api_base <> "/api/workflows/" <> workflow_id, 200)
  end

  @spec add_step(String.t(), String.t(), map()) :: map()
  def add_step(api_base, workflow_id, payload) do
    post_json!(api_base <> "/api/workflows/" <> workflow_id <> "/steps", payload, 201)
  end

  @spec add_parallel(String.t(), String.t(), [map()]) :: map()
  def add_parallel(api_base, workflow_id, steps) do
    post_json!(
      api_base <> "/api/workflows/" <> workflow_id <> "/parallel",
      %{"steps" => steps},
      201
    )
  end

  @spec add_merge(String.t(), String.t(), map()) :: map()
  def add_merge(api_base, workflow_id, payload) do
    post_json!(api_base <> "/api/workflows/" <> workflow_id <> "/merge", payload, 201)
  end

  @spec resume(String.t(), String.t(), String.t(), map()) :: map()
  def resume(api_base, workflow_id, step_id, output) do
    post_json!(
      api_base <> "/api/workflows/" <> workflow_id <> "/resume",
      %{"stepId" => step_id, "output" => output},
      200
    )
  end

  defp get_json!(url, expected_status) do
    case Req.get(url) do
      {:ok, %{status: ^expected_status, body: body}} when is_map(body) ->
        body

      {:ok, %{status: status, body: body}} ->
        raise "GET #{url} expected #{expected_status}, got #{status}: #{inspect(body)}"

      {:error, reason} ->
        raise "GET #{url} failed: #{inspect(reason)}"
    end
  end

  defp post_json!(url, payload, expected_status) do
    case Req.post(url, json: payload) do
      {:ok, %{status: ^expected_status, body: body}} when is_map(body) ->
        body

      {:ok, %{status: status, body: body}} ->
        raise "POST #{url} expected #{expected_status}, got #{status}: #{inspect(body)}"

      {:error, reason} ->
        raise "POST #{url} failed: #{inspect(reason)}"
    end
  end
end
