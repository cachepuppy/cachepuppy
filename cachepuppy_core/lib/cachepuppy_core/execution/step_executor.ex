defmodule CachePuppyCore.Execution.StepExecutor do
  @moduledoc """
  Stateless HTTP execution for a single workflow step: POST payload, validate status,
  retry with exponential backoff. Does not read or write workflow persistence.
  """

  alias CachePuppyCore.Execution.{HttpClient, Payload, RetryPolicy}
  alias CachePuppyCore.Workflow.Step

  @type success :: {:ok, %{status_code: non_neg_integer(), body: term(), step: Step.t()}}
  @type error ::
          {:error,
           %{
             required(:reason) => :max_retries_exceeded | :timeout | :connection_error,
             required(:attempts) => pos_integer(),
             optional(:last_status_code) => non_neg_integer() | nil,
             optional(:message) => String.t(),
             required(:step) => map()
           }}

  @doc """
  Executes `step` against `step.url` with JSON payload derived from `workflow_id`.

  Options:
  - `:merge_data` — if present, includes `mergeData` in the JSON body (use for merge steps).
  - `:timeout_ms` — per-request timeout (default from `:step_executor` config).
  - `:max_retries`, `:success_codes` — override policy for this call.
  - `:http_client` — module with `post_step/4` like `HttpClient` (for tests).
  - `:skip_sleep` — when true, skip backoff sleeps (for fast tests).
  """
  @spec execute(Step.t(), String.t(), keyword()) :: success() | error()
  def execute(%Step{} = step, workflow_id, opts \\ []) when is_binary(workflow_id) do
    merge_data =
      case Keyword.get(opts, :merge_data, :omit) do
        :omit -> :omit
        nil -> :omit
        md -> md
      end

    body = Payload.build_body(workflow_id, step, merge_data)
    headers = Payload.build_headers(workflow_id, step)

    http_mod = Keyword.get(opts, :http_client, HttpClient)
    timeout_ms = Keyword.get(opts, :timeout_ms, receive_timeout_ms())

    post_opts =
      [
        receive_timeout: timeout_ms,
        finch: Keyword.get(opts, :finch, CachePuppyCore.Finch)
      ]
      |> Keyword.merge(Keyword.get(opts, :http_client_opts, []))

    success_codes = RetryPolicy.effective_success_codes(step, opts)
    max_retries = RetryPolicy.effective_max_retries(step, opts)

    do_attempt(
      step,
      step.url,
      body,
      headers,
      post_opts,
      http_mod,
      success_codes,
      max_retries,
      1,
      opts
    )
  end

  defp receive_timeout_ms do
    RetryPolicy.config()
    |> Keyword.get(:receive_timeout_ms, 30_000)
  end

  defp do_attempt(
         step,
         url,
         body,
         headers,
         post_opts,
         http_mod,
         success_codes,
         max_retries,
         attempt,
         opts
       ) do
    case http_mod.post_step(url, body, headers, post_opts) do
      {:ok, %{status: status, body: resp_body}} ->
        if status in success_codes do
          failures = attempt - 1
          {:ok, %{status_code: status, body: resp_body, step: %{step | retry_count: failures}}}
        else
          handle_failure(
            step,
            url,
            body,
            headers,
            post_opts,
            http_mod,
            success_codes,
            max_retries,
            attempt,
            {:bad_status, status, resp_body},
            opts
          )
        end

      {:error, {:timeout, _msg}} ->
        handle_failure(
          step,
          url,
          body,
          headers,
          post_opts,
          http_mod,
          success_codes,
          max_retries,
          attempt,
          :timeout,
          opts
        )

      {:error, {:connection_error, msg}} ->
        handle_failure(
          step,
          url,
          body,
          headers,
          post_opts,
          http_mod,
          success_codes,
          max_retries,
          attempt,
          {:connection, msg},
          opts
        )
    end
  end

  defp handle_failure(
         step,
         url,
         body,
         headers,
         post_opts,
         http_mod,
         success_codes,
         max_retries,
         attempt,
         reason,
         opts
       ) do
    # attempt is the number of HTTP calls already made (including this failure).
    failures = attempt
    step = %{step | retry_count: failures}

    cond do
      attempt > max_retries ->
        finalize_error(reason, attempt, step)

      true ->
        RetryPolicy.sleep_before_retry!(attempt, opts)

        do_attempt(
          step,
          url,
          body,
          headers,
          post_opts,
          http_mod,
          success_codes,
          max_retries,
          attempt + 1,
          opts
        )
    end
  end

  defp finalize_error({:bad_status, status, _body}, attempts, step) do
    {:error,
     %{
       reason: :max_retries_exceeded,
       attempts: attempts,
       last_status_code: status,
       step: step_snapshot(step)
     }}
  end

  defp finalize_error(:timeout, attempts, step) do
    {:error, %{reason: :timeout, attempts: attempts, step: step_snapshot(step)}}
  end

  defp finalize_error({:connection, message}, attempts, step) do
    {:error,
     %{
       reason: :connection_error,
       attempts: attempts,
       message: message,
       step: step_snapshot(step)
     }}
  end

  defp step_snapshot(%Step{} = step) do
    %{
      step_id: step.step_id,
      step_name: step.step_name,
      url: step.url,
      method: step.method,
      status: step.status,
      retry_count: step.retry_count,
      max_retries: step.max_retries
    }
  end
end
