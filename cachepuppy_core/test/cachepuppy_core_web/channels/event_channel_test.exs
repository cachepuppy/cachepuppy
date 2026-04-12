defmodule CachePuppyCoreWeb.EventChannelTest do
  use ExUnit.Case, async: true
  import Phoenix.ChannelTest

  @endpoint CachePuppyCoreWeb.Endpoint

  test "join allows topic state operations" do
    topic = unique_topic()
    socket = user_socket("join_starts")

    {:ok, %{"connected_node" => _connected}, chan} =
      subscribe_and_join(socket, CachePuppyCoreWeb.EventChannel, "events:#{topic}")

    ref = push(chan, "get_state", %{})

    assert_reply ref, :ok, %{
      "state" => %{},
      "meta" => %{"source_node" => _source_node, "served_by_node" => _served_by_node}
    }
  end

  test "set_state broadcasts state_updated to all subscribers" do
    topic = unique_topic()
    socket_one = user_socket("state_subscriber_one")
    socket_two = user_socket("state_subscriber_two")

    {:ok, _reply, chan_one} =
      subscribe_and_join(socket_one, CachePuppyCoreWeb.EventChannel, "events:#{topic}")

    {:ok, _reply, chan_two} =
      subscribe_and_join(socket_two, CachePuppyCoreWeb.EventChannel, "events:#{topic}")

    ref = push(chan_one, "set_state", %{"payload" => %{"counter" => 2}})
    assert_reply ref, :ok, %{"state" => %{"counter" => 2}}

    assert_push "message", %{
      "event" => "state_updated",
      "payload" => %{"counter" => 2},
      "meta" => %{"source_node" => _source_node, "served_by_node" => _served_by_node}
    }

    assert_push "message", %{
      "event" => "state_updated",
      "payload" => %{"counter" => 2},
      "meta" => %{"source_node" => _source_node, "served_by_node" => _served_by_node}
    }

    ref = push(chan_two, "get_state", %{})

    assert_reply ref, :ok, %{
      "state" => %{"counter" => 2},
      "meta" => %{"source_node" => _source_node, "served_by_node" => _served_by_node}
    }
  end

  test "set_state with identical payload does not broadcast state_updated" do
    topic = unique_topic()
    socket = user_socket("idempotent_state")

    {:ok, _reply, chan} =
      subscribe_and_join(socket, CachePuppyCoreWeb.EventChannel, "events:#{topic}")

    ref1 = push(chan, "set_state", %{"payload" => %{"n" => 1}})
    assert_reply ref1, :ok, %{"state" => %{"n" => 1}}

    assert_push "message", %{
      "event" => "state_updated",
      "payload" => %{"n" => 1}
    }

    ref2 = push(chan, "set_state", %{"payload" => %{"n" => 1}})
    assert_reply ref2, :ok, %{"state" => %{"n" => 1}}

    refute_receive %Phoenix.Socket.Message{
      event: "message",
      payload: %{"event" => "state_updated"}
    }
  end

  test "close_topic stops process and get_state returns topic_not_found until rejoin" do
    topic = unique_topic()
    socket = user_socket("close_topic")

    {:ok, _reply, chan} =
      subscribe_and_join(socket, CachePuppyCoreWeb.EventChannel, "events:#{topic}")

    close_ref = push(chan, "close_topic", %{})
    assert_reply close_ref, :ok, %{"closed" => true}

    fetch_ref = push(chan, "get_state", %{})
    assert_reply fetch_ref, :error, %{reason: "topic_not_found"}

    Process.unlink(chan.channel_pid)

    {:ok, _reply, _new_chan} =
      subscribe_and_join(
        user_socket("close_topic_rejoin"),
        CachePuppyCoreWeb.EventChannel,
        "events:#{topic}"
      )

    ref = push(chan, "get_state", %{})

    assert_reply ref, :ok, %{
      "state" => %{},
      "meta" => %{"source_node" => _source_node, "served_by_node" => _served_by_node}
    }
  end

  defp user_socket(client_id) do
    Phoenix.ChannelTest.socket(CachePuppyCoreWeb.UserSocket, "usersocket:#{client_id}", %{
      client_id: client_id
    })
  end

  defp unique_topic do
    "event_channel_topic_#{System.unique_integer([:positive])}"
  end
end
