defmodule CachePuppyCore.CacheShardRehydrate do
  @moduledoc false

  import ExUnit.Assertions

  @doc """
  Calls `CacheShardProcess` `:rehydrate_sync` (synchronous replay). Works for both
  locally supervised shards (`name: nil`) and Horde-managed shards.

  Returns `:ok` on success or if the shard was already past `:none` (`{:ok, :skipped}`).
  """
  @spec rehydrate_sync!(pid()) :: :ok
  def rehydrate_sync!(pid) when is_pid(pid) do
    case GenServer.call(pid, :rehydrate_sync, :infinity) do
      :ok -> :ok
      {:ok, :skipped} -> :ok
      {:error, reason} -> flunk("rehydrate_sync failed: #{inspect(reason)}")
    end
  end

  @doc """
  Runs `rehydrate_sync!/1` then polls until `ready?` and `owner_valid?`.
  """
  @spec rehydrate_and_wait_ready!(pid(), keyword()) :: :ok
  def rehydrate_and_wait_ready!(pid, opts \\ []) when is_pid(pid) do
    rehydrate_sync!(pid)
    attempts = Keyword.get(opts, :attempts, 200)
    wait_ready!(pid, attempts)
  end

  defp wait_ready!(_pid, 0),
    do: flunk("shard did not become ready with valid ownership after rehydrate")

  defp wait_ready!(pid, attempts) do
    state = :sys.get_state(pid)

    if state.ready? and state.owner_valid? do
      :ok
    else
      receive do
      after
        10 -> wait_ready!(pid, attempts - 1)
      end
    end
  end
end
