defmodule CachePuppyCoreWeb.Changesets.ParallelMergeNowChangeset do
  @moduledoc false

  import Ecto.Changeset

  @types %{merge_step_id: :string}

  @spec validate_params(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def validate_params(params) when is_map(params) do
    cs =
      {%{}, @types}
      |> cast(%{merge_step_id: Map.get(params, "mergeStepId")}, [:merge_step_id])
      |> validate_required([:merge_step_id])

    if cs.valid?, do: {:ok, apply_changes(cs)}, else: {:error, cs}
  end
end
