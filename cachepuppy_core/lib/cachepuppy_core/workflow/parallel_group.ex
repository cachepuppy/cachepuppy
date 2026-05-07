defmodule CachePuppyCore.Workflow.ParallelGroup do
  @moduledoc false

  @type status :: :open | :waiting_for_merge_step | :completed | :failed

  @type t :: %__MODULE__{
          group_id: String.t(),
          total_branches: non_neg_integer(),
          completed_branches: non_neg_integer(),
          collected_outputs: [map()],
          merge_step_id: String.t() | nil,
          parent_group_id: String.t() | nil,
          status: status()
        }

  defstruct [
    :group_id,
    :total_branches,
    completed_branches: 0,
    collected_outputs: [],
    merge_step_id: nil,
    parent_group_id: nil,
    status: :open
  ]
end
