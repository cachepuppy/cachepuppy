defmodule CachePuppyCore.Execution.RetryPolicyTest do
  use ExUnit.Case, async: true

  alias CachePuppyCore.Execution.RetryPolicy
  alias CachePuppyCore.Workflow.Step

  test "delay_ms_before_retry follows exponential base with jitter bounds" do
    d1 = RetryPolicy.delay_ms_before_retry(1)
    assert d1 >= 1000 + 1 and d1 <= 1000 + 500

    d2 = RetryPolicy.delay_ms_before_retry(2)
    assert d2 >= 2000 + 1 and d2 <= 2000 + 500

    d3 = RetryPolicy.delay_ms_before_retry(3)
    assert d3 >= 4000 + 1 and d3 <= 4000 + 500
  end

  test "effective_success_codes falls back to default when step list empty" do
    step = %Step{
      step_id: "1",
      step_name: "s",
      url: "http://x",
      success_codes: []
    }

    assert RetryPolicy.effective_success_codes(step, []) == [200]
  end

  test "effective_max_retries uses step value when positive" do
    step = %Step{step_id: "1", step_name: "s", url: "http://x", max_retries: 2}
    assert RetryPolicy.effective_max_retries(step, []) == 2
  end

  test "effective_max_retries uses default when step max_retries is zero" do
    step = %Step{step_id: "1", step_name: "s", url: "http://x", max_retries: 0}
    assert RetryPolicy.effective_max_retries(step, []) == 3
  end

  test "opts override max_retries" do
    step = %Step{step_id: "1", step_name: "s", url: "http://x", max_retries: 5}
    assert RetryPolicy.effective_max_retries(step, max_retries: 1) == 1
  end
end
