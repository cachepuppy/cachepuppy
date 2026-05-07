defmodule CachePuppyCoreWeb.Changesets.ParallelChangesetTest do
  use ExUnit.Case, async: true

  alias CachePuppyCoreWeb.Changesets.ParallelChangeset

  test "validates parallel steps list" do
    params = %{
      "steps" => [
        %{"stepName" => "a", "url" => "https://x/a", "method" => "post"},
        %{"stepName" => "b", "url" => "https://x/b", "method" => "post"}
      ]
    }

    assert {:ok, steps} = ParallelChangeset.validate_params(params)
    assert length(steps) == 2
  end

  test "rejects empty steps list" do
    assert {:error, cs} = ParallelChangeset.validate_params(%{"steps" => []})
    refute cs.valid?
  end
end
