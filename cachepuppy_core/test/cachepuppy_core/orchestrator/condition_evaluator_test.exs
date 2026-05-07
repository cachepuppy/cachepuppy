defmodule CachePuppyCore.Orchestrator.ConditionEvaluatorTest do
  use ExUnit.Case, async: true

  alias CachePuppyCore.Orchestrator.ConditionEvaluator

  test "evaluates numeric comparison over nested result path" do
    assert {:ok, true} = ConditionEvaluator.evaluate("result.score < 0.8", %{"score" => 0.5})
    assert {:ok, false} = ConditionEvaluator.evaluate("result.score >= 0.8", %{"score" => 0.5})
  end

  test "evaluates equality and inequality" do
    assert {:ok, true} = ConditionEvaluator.evaluate("result.flag == true", %{"flag" => true})
    assert {:ok, true} = ConditionEvaluator.evaluate("result.flag != false", %{"flag" => true})
  end

  test "returns invalid_expression for unsupported forms" do
    assert {:error, :invalid_expression} =
             ConditionEvaluator.evaluate("result.score + 1", %{"score" => 1})

    assert {:error, :invalid_expression} = ConditionEvaluator.evaluate("bad", %{})
  end
end
