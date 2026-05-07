defmodule CachePuppyCoreWeb.Changesets.ParallelChangeset do
  @moduledoc false

  import Ecto.Changeset

  alias CachePuppyCoreWeb.Changesets.StepChangeset

  @types %{steps: {:array, :map}}

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(params) when is_map(params) do
    attrs = %{steps: Map.get(params, "steps")}

    {%{}, @types}
    |> cast(attrs, [:steps])
    |> validate_required([:steps])
    |> validate_change(:steps, fn :steps, steps ->
      cond do
        not is_list(steps) ->
          [steps: "must be a list"]

        length(steps) < 1 ->
          [steps: "must have at least 1 item"]

        length(steps) > 50 ->
          [steps: "must have at most 50 items"]

        true ->
          []
      end
    end)
  end

  @spec validate_params(map()) :: {:ok, [map()]} | {:error, Ecto.Changeset.t()}
  def validate_params(params) when is_map(params) do
    cs = changeset(params)

    if cs.valid? do
      steps = get_field(cs, :steps, [])

      step_results = Enum.map(steps, &StepChangeset.validate_params/1)

      case Enum.find(step_results, &match?({:error, _}, &1)) do
        nil ->
          {:ok, Enum.map(step_results, fn {:ok, step} -> step end)}

        {:error, step_cs} ->
          {:error,
           add_error(cs, :steps, "contains invalid step payload: #{inspect(humanize(step_cs))}")}
      end
    else
      {:error, cs}
    end
  end

  defp humanize(cs) do
    traverse_errors(cs, fn {msg, _opts} -> msg end)
  end
end
