defmodule CachePuppyCoreWeb.SessionChannelTest do
  use ExUnit.Case, async: true
  import Phoenix.ChannelTest
  alias CachePuppyCore.CacheShardSync
  alias CachePuppyCore.Persistence.CacheRouter
  alias CachePuppyCore.Persistence.CacheShardRead

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

  test "set/get/delete cache data through session channel" do
    {:ok, _reply, chan} =
      subscribe_and_join(
        user_socket("session_cache_client"),
        CachePuppyCoreWeb.SessionChannel,
        "session"
      )

    :ok = CacheShardSync.sync!("users", "alice")

    set_payload = %{
      "table" => "users",
      "key" => "alice",
      "value" => %{"role" => "admin"}
    }

    assert eventually_ok_reply(chan, "set_cache_data", set_payload) == %{
             "table" => "users",
             "key" => "alice",
             "value" => %{"role" => "admin"}
           }

    assert eventually_ok_reply(chan, "get_cache_data", %{"table" => "users", "key" => "alice"}) ==
             %{
               "table" => "users",
               "key" => "alice",
               "value" => %{"role" => "admin"}
             }

    assert eventually_ok_reply(chan, "delete_cache_data", %{"table" => "users", "key" => "alice"}) ==
             %{
               "table" => "users",
               "key" => "alice",
               "deleted" => true
             }

    assert eventually_ok_reply(chan, "get_cache_data", %{"table" => "users", "key" => "alice"}) ==
             %{
               "table" => "users",
               "key" => "alice",
               "value" => nil
             }
  end

  test "set_cache_data validates ttl_ms and payload" do
    {:ok, _reply, chan} =
      subscribe_and_join(
        user_socket("session_cache_ttl_client"),
        CachePuppyCoreWeb.SessionChannel,
        "session"
      )

    bad_ttl_ref =
      push(chan, "set_cache_data", %{
        "table" => "users",
        "key" => "bob",
        "value" => %{"role" => "viewer"},
        "ttl_ms" => 0
      })

    assert_reply bad_ttl_ref, :error, %{reason: "invalid_ttl_ms"}

    bad_payload_ref = push(chan, "set_cache_data", %{"table" => "users", "key" => "bob"})
    assert_reply bad_payload_ref, :error, %{reason: "invalid_payload"}
  end

  test "get_cache_data maps rehydrating errors" do
    table = "rehydrating_table_#{System.unique_integer([:positive])}"
    key = "rehydrating_key"
    {:ok, shard_id} = CacheRouter.shard_id_for_entry(table, key)
    table_tid = :ets.new(__MODULE__, [:set, :protected])

    CacheShardRead.publish_rehydrating(shard_id, table_tid, 1)

    try do
      {:ok, _reply, chan} =
        subscribe_and_join(
          user_socket("session_cache_rehydrating_client"),
          CachePuppyCoreWeb.SessionChannel,
          "session"
        )

      ref = push(chan, "get_cache_data", %{"table" => table, "key" => key})
      assert_reply ref, :error, %{reason: "rehydrating"}
    after
      CacheShardRead.clear(self())
      :ets.delete(table_tid)
    end
  end

  defp user_socket(client_id) do
    Phoenix.ChannelTest.socket(CachePuppyCoreWeb.UserSocket, "usersocket:#{client_id}", %{
      client_id: client_id
    })
  end

  defp eventually_ok_reply(chan, event, payload, attempts \\ 8)

  defp eventually_ok_reply(_chan, _event, _payload, 0) do
    flunk("expected eventual :ok reply but rehydrating persisted")
  end

  defp eventually_ok_reply(chan, event, payload, attempts) do
    ref = push(chan, event, payload)

    receive do
      %Phoenix.Socket.Reply{ref: ^ref, status: :ok, payload: response_payload} ->
        response_payload

      %Phoenix.Socket.Reply{ref: ^ref, status: :error, payload: %{reason: "rehydrating"}} ->
        Process.sleep(20)
        eventually_ok_reply(chan, event, payload, attempts - 1)

      %Phoenix.Socket.Reply{ref: ^ref, status: :error, payload: error_payload} ->
        flunk("unexpected error reply: #{inspect(error_payload)}")
    after
      500 ->
        flunk("timed out waiting for reply")
    end
  end
end
