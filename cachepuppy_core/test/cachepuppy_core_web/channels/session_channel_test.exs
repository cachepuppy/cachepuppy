defmodule CachePuppyCoreWeb.SessionChannelTest do
  use ExUnit.Case, async: true
  import Phoenix.ChannelTest

  @endpoint CachePuppyCoreWeb.Endpoint

  test "join returns client_id and empty session" do
    client_id = "session_join_client"
    socket = user_socket(client_id)

    {:ok, %{"connected_node" => _node, "client_id" => ^client_id}, _chan} =
      subscribe_and_join(socket, CachePuppyCoreWeb.SessionChannel, "session")
  end

  test "set_session_state and get_session_state are scoped to each connection" do
    client_id = "session_scoped_client"

    {:ok, _reply, chan_one} =
      subscribe_and_join(user_socket(client_id), CachePuppyCoreWeb.SessionChannel, "session")

    {:ok, _reply, chan_two} =
      subscribe_and_join(user_socket(client_id), CachePuppyCoreWeb.SessionChannel, "session")

    set_ref = push(chan_one, "set_session_state", %{"payload" => %{"theme" => "dark"}})
    assert_reply set_ref, :ok, %{"state" => %{"theme" => "dark"}}

    get_first_ref = push(chan_one, "get_session_state", %{})
    assert_reply get_first_ref, :ok, %{"state" => %{"theme" => "dark"}}

    get_second_ref = push(chan_two, "get_session_state", %{})
    assert_reply get_second_ref, :ok, %{"state" => %{}}
  end

  test "session state resets on reconnect for same client_id" do
    client_id = "session_reconnect_client"

    {:ok, _reply, chan_one} =
      subscribe_and_join(user_socket(client_id), CachePuppyCoreWeb.SessionChannel, "session")

    set_ref = push(chan_one, "set_session_state", %{"payload" => %{"count" => 7}})
    assert_reply set_ref, :ok, %{"state" => %{"count" => 7}}

    get_ref = push(chan_one, "get_session_state", %{})
    assert_reply get_ref, :ok, %{"state" => %{"count" => 7}}

    Process.unlink(chan_one.channel_pid)
    leave(chan_one)

    {:ok, _reply, chan_two} =
      subscribe_and_join(user_socket(client_id), CachePuppyCoreWeb.SessionChannel, "session")

    get_fresh_ref = push(chan_two, "get_session_state", %{})
    assert_reply get_fresh_ref, :ok, %{"state" => %{}}
  end

  defp user_socket(client_id) do
    Phoenix.ChannelTest.socket(CachePuppyCoreWeb.UserSocket, "usersocket:#{client_id}", %{client_id: client_id})
  end
end
