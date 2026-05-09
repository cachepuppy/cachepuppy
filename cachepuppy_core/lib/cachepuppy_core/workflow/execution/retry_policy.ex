defmodule CachePuppyCore.Execution.RetryPolicy do
  @moduledoc """
  Backoff and effective limits for step HTTP execution.

  Max retries: when `step.max_retries` is greater than 0, that value is used; otherwise
  the application default applies (typically 3). A positive `step.max_retries` is the
  only way to force a lower or higher count from the step struct; `0` means "use default".
  """

  @base_ms 1_000
  @jitter_max_ms 500

  @spec config() :: keyword()
  def config do
    Application.get_env(:cachepuppy_core, :step_executor, [])
  end

  @spec effective_success_codes(CachePuppyCore.Workflow.Step.t(), keyword()) :: [
          non_neg_integer()
        ]
  def effective_success_codes(step, opts) do
    codes =
      case Keyword.get(opts, :success_codes) do
        nil -> step.success_codes
        c -> c
      end

    if codes == nil or codes == [] do
      Keyword.get(config(), :default_success_codes, [200])
    else
      codes
    end
  end

  @spec effective_max_retries(CachePuppyCore.Workflow.Step.t(), keyword()) :: non_neg_integer()
  def effective_max_retries(step, opts) do
    case Keyword.get(opts, :max_retries) do
      n when is_integer(n) and n >= 0 ->
        n

      nil ->
        if step.max_retries > 0 do
          step.max_retries
        else
          Keyword.get(config(), :default_max_retries, 3)
        end
    end
  end

  @doc """
  Delay before HTTP attempt number `retry_number`, where `retry_number` is 1 for the
  first retry (i.e. after the initial request failed).

  `delay_ms = 1000 * 2^(retry_number - 1) + jitter`, jitter in `1..500`.
  """
  @spec delay_ms_before_retry(pos_integer()) :: non_neg_integer()
  def delay_ms_before_retry(retry_number) when is_integer(retry_number) and retry_number >= 1 do
    trunc(@base_ms * :math.pow(2, retry_number - 1)) + :rand.uniform(@jitter_max_ms)
  end

  @spec sleep_before_retry!(pos_integer(), keyword()) :: :ok
  def sleep_before_retry!(retry_number, opts)
      when is_integer(retry_number) and retry_number >= 1 do
    if Keyword.get(opts, :skip_sleep, false) do
      :ok
    else
      retry_number
      |> delay_ms_before_retry()
      |> Process.sleep()
    end
  end
end
