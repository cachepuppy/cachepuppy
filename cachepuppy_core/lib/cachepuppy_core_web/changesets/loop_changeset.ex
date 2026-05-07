defmodule CachePuppyCoreWeb.Changesets.LoopChangeset do
  @moduledoc false

  import Ecto.Changeset

  alias CachePuppyCoreWeb.Changesets.StepChangeset

  @types %{
    step_name: :string,
    url: :string,
    method: :string,
    data: :map,
    success_codes: {:array, :integer},
    max_retries: :integer,
    continue_if: :string,
    max_iterations: :integer
  }

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(params) when is_map(params) do
    attrs = %{
      step_name: Map.get(params, "stepName"),
      url: Map.get(params, "url"),
      method: Map.get(params, "method"),
      data: Map.get(params, "data"),
      success_codes: Map.get(params, "successCodes"),
      max_retries: Map.get(params, "maxRetries"),
      continue_if: Map.get(params, "continueIf"),
      max_iterations: Map.get(params, "maxIterations")
    }

    {%{}, @types}
    |> cast(attrs, Map.keys(@types))
    |> StepChangeset.apply_common_validations()
    |> validate_required([:step_name, :url, :method, :continue_if, :max_iterations])
    |> validate_length(:continue_if, max: 200)
    |> validate_number(:max_iterations, greater_than_or_equal_to: 1, less_than_or_equal_to: 100)
  end

  @spec validate_params(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def validate_params(params) when is_map(params) do
    cs = changeset(params)
    if cs.valid?, do: {:ok, apply_changes(cs)}, else: {:error, cs}
  end
end
