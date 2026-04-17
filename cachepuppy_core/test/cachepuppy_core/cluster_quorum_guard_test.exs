defmodule CachePuppyCore.ClusterQuorumGuardTest do
  use ExUnit.Case, async: false

  alias CachePuppyCore.ClusterQuorumGuard

  test "stays healthy when quorum is met" do
    with_quorum_env(1, 10, 30, fn ->
      _pid = start_supervised!({ClusterQuorumGuard, []})
      _ = :sys.get_state(ClusterQuorumGuard)

      assert ClusterQuorumGuard.mode() == :healthy
      refute ClusterQuorumGuard.snapshot_blocked?()
      assert ClusterQuorumGuard.quorum_status().quorum_met
    end)
  end

  test "enters grace then fenced when quorum is not met through grace deadline" do
    with_quorum_env(3, 10, 30, fn ->
      _pid = start_supervised!({ClusterQuorumGuard, []})

      wait_until(fn -> ClusterQuorumGuard.mode() == :grace end)
      assert ClusterQuorumGuard.snapshot_blocked?()

      wait_until(fn -> ClusterQuorumGuard.mode() == :fenced end)
      assert ClusterQuorumGuard.snapshot_blocked?()
    end)
  end

  test "returns to healthy when quorum is restored during grace period" do
    with_quorum_env(3, 10, 500, fn ->
      _pid = start_supervised!({ClusterQuorumGuard, []})

      wait_until(fn -> ClusterQuorumGuard.mode() == :grace end)
      Application.put_env(:cachepuppy_core, :cache_expected_nodes, 1)
      wait_until(fn -> ClusterQuorumGuard.mode() == :healthy end)
      refute ClusterQuorumGuard.snapshot_blocked?()
    end)
  end

  defp with_quorum_env(expected_nodes, poll_interval_ms, grace_ms, fun) do
    old_expected_nodes = Application.get_env(:cachepuppy_core, :cache_expected_nodes)
    old_poll = Application.get_env(:cachepuppy_core, :cache_quorum_poll_interval_ms)
    old_grace = Application.get_env(:cachepuppy_core, :cache_quorum_grace_ms)
    old_stop_enabled = Application.get_env(:cachepuppy_core, :cache_quorum_stop_enabled)

    Application.put_env(:cachepuppy_core, :cache_expected_nodes, expected_nodes)
    Application.put_env(:cachepuppy_core, :cache_quorum_poll_interval_ms, poll_interval_ms)
    Application.put_env(:cachepuppy_core, :cache_quorum_grace_ms, grace_ms)
    Application.put_env(:cachepuppy_core, :cache_quorum_stop_enabled, false)

    try do
      fun.()
    after
      restore_env(:cache_expected_nodes, old_expected_nodes)
      restore_env(:cache_quorum_poll_interval_ms, old_poll)
      restore_env(:cache_quorum_grace_ms, old_grace)
      restore_env(:cache_quorum_stop_enabled, old_stop_enabled)
      :persistent_term.put({CachePuppyCore.ClusterQuorumGuard, :snapshot_blocked}, false)
      :persistent_term.put({CachePuppyCore.ClusterQuorumGuard, :mode}, :healthy)
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:cachepuppy_core, key)
  defp restore_env(key, value), do: Application.put_env(:cachepuppy_core, key, value)

  defp wait_until(fun, attempts \\ 200)
  defp wait_until(_fun, 0), do: flunk("condition not met")

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      receive do
      after
        10 -> wait_until(fun, attempts - 1)
      end
    end
  end
end
