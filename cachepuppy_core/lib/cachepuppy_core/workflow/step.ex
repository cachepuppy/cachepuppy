defmodule CachePuppyCore.Workflow.Step do
  @moduledoc false

  @type status :: :pending | :running | :completed | :failed

  @type t :: %__MODULE__{
          step_id: String.t(),
          step_name: String.t(),
          url: String.t(),
          method: String.t(),
          data: term(),
          status: status(),
          success_codes: [non_neg_integer()],
          max_retries: non_neg_integer(),
          retry_count: non_neg_integer(),
          input: term(),
          output: term(),
          parent_ids: [String.t()],
          group_id: String.t() | nil,
          group_type: :parallel_branch | :parallel_merge | nil,
          parent_group_id: String.t() | nil,
          execution_error: term() | nil,
          branch_index: non_neg_integer() | nil,
          inserted_at: DateTime.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil
        }

  defstruct [
    :step_id,
    :step_name,
    :url,
    method: "POST",
    data: nil,
    status: :pending,
    success_codes: [200, 201],
    max_retries: 0,
    retry_count: 0,
    input: nil,
    output: nil,
    parent_ids: [],
    group_id: nil,
    group_type: nil,
    parent_group_id: nil,
    execution_error: nil,
    branch_index: nil,
    inserted_at: nil,
    started_at: nil,
    completed_at: nil
  ]
end
