defmodule CachePuppyCoreWeb.Changesets.ParallelChangesetTest do
  use ExUnit.Case, async: true

  alias CachePuppyCoreWeb.Changesets.ParallelChangeset

  test "validates parallel steps list" do
    params = %{
      "steps" => [
        %{"stepName" => "a", "url" => "https://x/a", "method" => "post"},
        %{"stepName" => "b", "url" => "https://x/b", "method" => "post"}
      ],
      "mergeStep" => %{"stepName" => "merge", "url" => "https://x/m", "method" => "post"}
    }

    assert {:ok, payload} = ParallelChangeset.validate_params(params)
    assert length(payload.steps) == 2
    assert payload.merge_step.step_name == "merge"
  end

  test "rejects empty steps list" do
    assert {:error, cs} =
             ParallelChangeset.validate_params(%{
               "steps" => [],
               "mergeStep" => %{"stepName" => "m", "url" => "https://x/m", "method" => "post"}
             })

    refute cs.valid?
  end
end
