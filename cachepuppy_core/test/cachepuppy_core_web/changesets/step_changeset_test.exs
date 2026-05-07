defmodule CachePuppyCoreWeb.Changesets.StepChangesetTest do
  use ExUnit.Case, async: true

  alias CachePuppyCoreWeb.Changesets.StepChangeset

  test "valid step payload applies defaults" do
    params = %{
      "stepName" => "extract",
      "url" => "https://myapp.com/extract",
      "method" => "post"
    }

    assert {:ok, valid} = StepChangeset.validate_params(params)
    assert valid.data == %{}
    assert valid.success_codes == [200]
    assert valid.max_retries == 3
  end

  test "rejects invalid method and url" do
    params = %{
      "stepName" => "extract",
      "url" => "ftp://example.com",
      "method" => "trace"
    }

    assert {:error, cs} = StepChangeset.validate_params(params)
    refute cs.valid?
  end
end
