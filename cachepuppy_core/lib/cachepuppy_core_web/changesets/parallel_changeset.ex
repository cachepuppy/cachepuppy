defmodule CachePuppyCoreWeb.Changesets.ParallelChangeset do
  @moduledoc false

  import Ecto.Changeset

  alias CachePuppyCoreWeb.Changesets.StepChangeset

  @types %{steps: {:array, :map}, merge_step: :map}

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(params) when is_map(params) do
    attrs = %{steps: Map.get(params, "steps"), merge_step: Map.get(params, "mergeStep")}

    {%{}, @types}
    |> cast(attrs, [:steps, :merge_step])
    |> validate_required([:steps, :merge_step])
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

  @spec validate_params(map()) :: {:ok, %{steps: [map()], merge_step: map()}} | {:error, Ecto.Changeset.t()}
  def validate_params(params) when is_map(params) do
    cs = changeset(params)

    if cs.valid? do
      steps = get_field(cs, :steps, [])
      merge_step = get_field(cs, :merge_step, %{})

      step_results = Enum.map(steps, &StepChangeset.validate_params/1)
      merge_result = StepChangeset.validate_params(merge_step)

      case {Enum.find(step_results, &match?({:error, _}, &1)), merge_result} do
        {nil, {:ok, merge}} ->
          {:ok, %{steps: Enum.map(step_results, fn {:ok, step} -> step end), merge_step: merge}}

        {{:error, step_cs}, _} ->
          {:error, add_error(cs, :steps, "contains invalid step payload: #{inspect(humanize(step_cs))}")}

        {_, {:error, merge_cs}} ->
          {:error, add_error(cs, :mergeStep, "invalid merge step payload: #{inspect(humanize(merge_cs))}")}
      end
    else
      {:error, cs}
    end
  end

  defp humanize(cs) do
    traverse_errors(cs, fn {msg, _opts} -> msg end)
  end
end
