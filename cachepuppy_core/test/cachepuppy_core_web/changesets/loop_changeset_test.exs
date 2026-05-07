defmodule CachePuppyCoreWeb.Changesets.LoopChangesetTest do
  use ExUnit.Case, async: true

  alias CachePuppyCoreWeb.Changesets.LoopChangeset

  test "valid loop payload" do
    params = %{
      "stepName" => "refine",
      "url" => "https://myapp.com/refine",
      "method" => "post",
      "continueIf" => "result.score < 0.8",
      "maxIterations" => 20
    }

    assert {:ok, valid} = LoopChangeset.validate_params(params)
    assert valid.max_iterations == 20
  end

  test "rejects invalid maxIterations" do
    params = %{
      "stepName" => "refine",
      "url" => "https://myapp.com/refine",
      "method" => "post",
      "continueIf" => "result.score < 0.8",
      "maxIterations" => 0
    }

    assert {:error, cs} = LoopChangeset.validate_params(params)
    refute cs.valid?
  end
end
