defmodule CachePuppyCore.TopicProcessTest do
  use ExUnit.Case, async: true

  alias CachePuppyCore.TopicProcess

  test "set_state and get_state return shared topic state" do
    topic = "topic_process_test_#{System.unique_integer([:positive])}"
    pid = start_supervised!({TopicProcess, topic: topic, idle_timeout_ms: 5_000})
    _ = :sys.get_state(pid)

    assert {:ok, %{"count" => 1}} = TopicProcess.set_state(topic, %{"count" => 1})
    assert {:ok, %{"count" => 1}} = TopicProcess.get_state(topic)
  end

  test "process exits after idle timeout" do
    topic = "topic_process_idle_#{System.unique_integer([:positive])}"
    pid = start_supervised!({TopicProcess, topic: topic, idle_timeout_ms: 20})
    ref = Process.monitor(pid)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
  end
end
