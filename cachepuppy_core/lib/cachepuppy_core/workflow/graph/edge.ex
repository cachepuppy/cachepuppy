defmodule CachePuppyCore.Graph.Edge do
  @moduledoc false

  @type edge_type :: :serial | :fan_out | :fan_in
  @type t :: %{required(String.t()) => String.t()}

  @spec build(String.t(), String.t(), edge_type()) :: t()
  def build(from, to, type) when is_binary(from) and is_binary(to) do
    %{"from" => from, "to" => to, "type" => Atom.to_string(type)}
  end
end
