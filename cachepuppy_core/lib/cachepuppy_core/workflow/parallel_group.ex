defmodule CachePuppyCore.Workflow.ParallelGroup do
  @moduledoc false

  @type status :: :open | :merge_waiting | :completed | :failed

  @type t :: %__MODULE__{
          group_id: String.t(),
          total_branches: non_neg_integer(),
          completed_branches: non_neg_integer(),
          collected_outputs: [map()],
          merge_step_id: String.t() | nil,
          branch_root_step_ids: [String.t()],
          branch_terminal_step_ids: %{String.t() => String.t()},
          merge_armed: boolean(),
          parent_group_id: String.t() | nil,
          status: status()
        }

  defstruct [
    :group_id,
    :total_branches,
    completed_branches: 0,
    collected_outputs: [],
    merge_step_id: nil,
    branch_root_step_ids: [],
    branch_terminal_step_ids: %{},
    merge_armed: false,
    parent_group_id: nil,
    status: :open
  ]
end
