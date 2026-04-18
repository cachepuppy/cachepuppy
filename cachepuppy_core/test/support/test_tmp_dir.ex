defmodule CachePuppyCore.TestTmpDir do
  @moduledoc false

  @doc """
  Returns a path under the system temp directory that is extremely unlikely to
  collide across `mix test` invocations. `System.unique_integer/1` alone resets
  for each new BEAM VM, so low integers repeat often and stale WAL files from
  a prior run can skew recovery/open state.
  """
  def path(name_prefix) when is_binary(name_prefix) do
    Path.join(
      System.tmp_dir!(),
      "#{name_prefix}_#{System.system_time(:nanosecond)}_#{:erlang.unique_integer([:positive, :monotonic])}"
    )
  end
end
