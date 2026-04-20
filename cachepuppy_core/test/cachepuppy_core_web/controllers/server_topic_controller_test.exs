defmodule CachePuppyCoreWeb.ServerTopicControllerTest do
  use CachePuppyCoreWeb.ConnCase, async: false
  import Phoenix.ChannelTest

  @endpoint CachePuppyCoreWeb.Endpoint

  test "HTTP put then get state matches channel semantics" do
    topic = unique_topic()
    path = "/api/server/v1/topics/#{topic}/state"
    body = Jason.encode!(%{"counter" => 3})

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put(path, body)

    assert %{"state" => %{"counter" => 3}} = json_response(conn, 200)

    conn =
      build_conn()
      |> get(path)

    assert %{
             "state" => %{"counter" => 3},
             "meta" => %{"source_node" => _, "served_by_node" => _}
           } = json_response(conn, 200)
  end

  test "HTTP put state broadcasts state_updated to joined websocket clients" do
    topic = unique_topic()
    socket_one = user_socket("http_state_one")
    socket_two = user_socket("http_state_two")

    {:ok, _reply, _chan_one} =
      subscribe_and_join(socket_one, CachePuppyCoreWeb.EventChannel, "events:#{topic}")

    {:ok, _reply, _chan_two} =
      subscribe_and_join(socket_two, CachePuppyCoreWeb.EventChannel, "events:#{topic}")

    path = "/api/server/v1/topics/#{topic}/state"
    body = Jason.encode!(%{"counter" => 2})

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put(path, body)

    assert json_response(conn, 200)["state"] == %{"counter" => 2}

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
  end

  test "HTTP post message delivers publish envelope to subscribers" do
    topic = unique_topic()
    socket_one = user_socket("http_msg_one")
    socket_two = user_socket("http_msg_two")

    {:ok, _reply, _} =
      subscribe_and_join(socket_one, CachePuppyCoreWeb.EventChannel, "events:#{topic}")

    {:ok, _reply, _} =
      subscribe_and_join(socket_two, CachePuppyCoreWeb.EventChannel, "events:#{topic}")

    path = "/api/server/v1/topics/#{topic}/messages"
    body = Jason.encode!(%{"event" => "order_created", "payload" => %{"id" => "o1"}})

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(path, body)

    assert json_response(conn, 202) == %{"ok" => true}

    assert_push "message", %{
      "v" => 1,
      "type" => "publish",
      "topic" => ^topic,
      "event" => "order_created",
      "payload" => %{"id" => "o1"},
      "meta" => %{"clientId" => "server_api", "source_node" => _, "served_by_node" => _}
    }

    assert_push "message", %{
      "v" => 1,
      "type" => "publish",
      "topic" => ^topic,
      "event" => "order_created",
      "payload" => %{"id" => "o1"},
      "meta" => %{"clientId" => "server_api", "source_node" => _, "served_by_node" => _}
    }
  end

  test "HTTP get presence returns client_count for joined sockets" do
    topic = unique_topic()
    sock_a = user_socket("presence_a")
    sock_b = user_socket("presence_b")

    {:ok, _reply, _} =
      subscribe_and_join(sock_a, CachePuppyCoreWeb.EventChannel, "events:#{topic}")

    {:ok, _reply, _} =
      subscribe_and_join(sock_b, CachePuppyCoreWeb.EventChannel, "events:#{topic}")

    conn =
      build_conn()
      |> get("/api/server/v1/topics/#{topic}/presence")

    assert %{"client_count" => 2, "presence" => presence} = json_response(conn, 200)
    assert map_size(presence) == 2
  end

  test "HTTP delete topic stops process; get state returns not found until state is set again" do
    topic = unique_topic()
    base = "/api/server/v1/topics/#{topic}"

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put("#{base}/state", Jason.encode!(%{"n" => 1}))

    assert json_response(conn, 200)["state"] == %{"n" => 1}

    conn = build_conn() |> delete(base)
    assert json_response(conn, 200) == %{"closed" => true}

    conn = build_conn() |> get("#{base}/state")
    assert json_response(conn, 404)["reason"] == "topic_not_found"

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put("#{base}/state", Jason.encode!(%{}))

    assert json_response(conn, 200) == %{"state" => %{}}

    conn = build_conn() |> get("#{base}/state")
    assert %{"state" => %{}, "meta" => _} = json_response(conn, 200)
  end

  test "post message rejects missing event" do
    topic = unique_topic()
    path = "/api/server/v1/topics/#{topic}/messages"
    body = Jason.encode!(%{"payload" => %{}})

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(path, body)

    assert json_response(conn, 400)["reason"] == "invalid_payload"
  end

  defp user_socket(client_id) do
    Phoenix.ChannelTest.socket(CachePuppyCoreWeb.UserSocket, "usersocket:#{client_id}", %{
      client_id: client_id
    })
  end

  defp unique_topic do
    "server_topic_api_#{System.unique_integer([:positive])}"
  end
end
