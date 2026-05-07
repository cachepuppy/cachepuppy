defmodule CachePuppyCore.Workflow.LoopIteration do
  @moduledoc false

  @type t :: %__MODULE__{
          step_id: String.t(),
          input: term(),
          output: term(),
          status: CachePuppyCore.Workflow.Step.status()
        }

  defstruct [:step_id, :input, :output, status: :pending]
end
