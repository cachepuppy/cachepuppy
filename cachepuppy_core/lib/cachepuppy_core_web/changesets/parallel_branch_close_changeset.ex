defmodule CachePuppyCoreWeb.Changesets.ParallelBranchCloseChangeset do
  @moduledoc false

  import Ecto.Changeset

  @types %{branch_id: :string, terminal_step_id: :string}

  @spec validate_params(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def validate_params(params) when is_map(params) do
    cs =
      {%{}, @types}
      |> cast(
        %{branch_id: Map.get(params, "branchId"), terminal_step_id: Map.get(params, "terminalStepId")},
        [:branch_id, :terminal_step_id]
      )
      |> validate_required([:branch_id, :terminal_step_id])

    if cs.valid?, do: {:ok, apply_changes(cs)}, else: {:error, cs}
  end
end
