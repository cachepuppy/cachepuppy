defmodule CachePuppyCore.Workflow.LoopGroup do
  @moduledoc false

  alias CachePuppyCore.Workflow.LoopIteration

  @type status :: :running | :completed

  @type t :: %__MODULE__{
          group_id: String.t(),
          step_name: String.t(),
          continue_if: String.t(),
          max_iterations: non_neg_integer(),
          current_iteration: non_neg_integer(),
          template_step_id: String.t(),
          parent_group_id: String.t() | nil,
          iterations: [LoopIteration.t()],
          status: status()
        }

  defstruct [
    :group_id,
    :step_name,
    :continue_if,
    :max_iterations,
    :template_step_id,
    parent_group_id: nil,
    current_iteration: 0,
    iterations: [],
    status: :running
  ]
end
