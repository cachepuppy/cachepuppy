defmodule CachePuppyCore.Graph do
  @moduledoc false

  alias CachePuppyCore.Graph.{Edge, Node}

  @type t :: %__MODULE__{
          workflow_id: String.t(),
          name: String.t() | nil,
          status: String.t(),
          nodes: [Node.t()],
          edges: [Edge.t()],
          updated_at: String.t()
        }

  defstruct [:workflow_id, :name, :status, nodes: [], edges: [], updated_at: nil]
end

