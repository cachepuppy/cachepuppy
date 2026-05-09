defmodule CachePuppyCore.Workflow do
  @moduledoc false

  alias CachePuppyCore.Workflow.{ParallelGroup, Step}

  @type status :: :pending | :running | :waiting | :failing | :completed | :failed

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          status: status(),
          steps: %{String.t() => Step.t()},
          groups: %{String.t() => ParallelGroup.t()},
          open_parallel_group_id: String.t() | nil,
          serial_tail_step_id: String.t() | nil,
          active_step_ids: MapSet.t(String.t()),
          failed_step_ids: [String.t()],
          failure_reason: term() | nil,
          graph_snapshot: CachePuppyCore.Graph.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :name,
    status: :pending,
    steps: %{},
    groups: %{},
    open_parallel_group_id: nil,
    serial_tail_step_id: nil,
    active_step_ids: MapSet.new(),
    failed_step_ids: [],
    failure_reason: nil,
    graph_snapshot: nil,
    inserted_at: nil,
    updated_at: nil
  ]

  @spec new(String.t(), String.t() | nil) :: t()
  def new(id, name \\ nil) when is_binary(id) and (is_binary(name) or is_nil(name)) do
    now = DateTime.utc_now()
    %__MODULE__{id: id, name: name, inserted_at: now, updated_at: now}
  end
end
