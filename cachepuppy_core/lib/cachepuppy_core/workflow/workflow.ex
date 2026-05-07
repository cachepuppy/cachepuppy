defmodule CachePuppyCore.Workflow do
  @moduledoc false

  alias CachePuppyCore.Workflow.{LoopGroup, ParallelGroup, Step}

  @type status :: :pending | :running | :waiting | :completed | :failed

  @type t :: %__MODULE__{
          id: String.t(),
          status: status(),
          steps: %{String.t() => Step.t()},
          groups: %{String.t() => ParallelGroup.t() | LoopGroup.t()},
          open_parallel_group_id: String.t() | nil,
          serial_tail_step_id: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    status: :pending,
    steps: %{},
    groups: %{},
    open_parallel_group_id: nil,
    serial_tail_step_id: nil,
    inserted_at: nil,
    updated_at: nil
  ]

  @spec new(String.t()) :: t()
  def new(id) when is_binary(id) do
    now = DateTime.utc_now()
    %__MODULE__{id: id, inserted_at: now, updated_at: now}
  end
end
