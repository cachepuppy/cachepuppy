defmodule CachePuppyCoreWeb.EventChannelWebhookTest do
  use ExUnit.Case, async: false
  import Phoenix.ChannelTest

  @endpoint CachePuppyCoreWeb.Endpoint

  test "configure_topic_webhook and tick posts JSON when state changed" do
    bypass = Bypass.open()
    topic = "webhook_topic_#{System.unique_integer([:positive])}"
    url = "http://127.0.0.1:#{bypass.port}/hook"

    Bypass.expect_once(bypass, "POST", "/hook", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["topic"] == topic
      assert decoded["state"] == %{"x" => 1}
      assert is_integer(decoded["ts"])
      Plug.Conn.resp(conn, 200, "ok")
    end)

    socket = user_socket("wh_client_1")

    {:ok, _reply, chan} =
      subscribe_and_join(socket, CachePuppyCoreWeb.EventChannel, "events:#{topic}")

    ref_cfg =
      push(chan, "configure_topic_webhook", %{
        "flush" => true,
        "url" => url,
        "frequency" => 1
      })

    assert_reply ref_cfg, :ok

    ref_st = push(chan, "set_state", %{"payload" => %{"x" => 1}})
    assert_reply ref_st, :ok, %{"state" => %{"x" => 1}}

    Process.sleep(1200)
  end

  test "multiple state updates before one tick yield single POST with latest state" do
    bypass = Bypass.open()
    topic = "webhook_coalesce_#{System.unique_integer([:positive])}"
    url = "http://127.0.0.1:#{bypass.port}/hook"

    Bypass.expect_once(bypass, "POST", "/hook", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["topic"] == topic
      assert decoded["state"] == %{"v" => 2}
      Plug.Conn.resp(conn, 200, "ok")
    end)

    socket = user_socket("wh_client_2")

    {:ok, _reply, chan} =
      subscribe_and_join(socket, CachePuppyCoreWeb.EventChannel, "events:#{topic}")

    assert_reply(
      push(chan, "configure_topic_webhook", %{
        "flush" => true,
        "url" => url,
        "frequency" => 2
      }),
      :ok
    )

    assert_reply push(chan, "set_state", %{"payload" => %{"v" => 0}}), :ok, %{
      "state" => %{"v" => 0}
    }

    assert_reply push(chan, "set_state", %{"payload" => %{"v" => 1}}), :ok, %{
      "state" => %{"v" => 1}
    }

    assert_reply push(chan, "set_state", %{"payload" => %{"v" => 2}}), :ok, %{
      "state" => %{"v" => 2}
    }

    Process.sleep(2500)
  end

  defp user_socket(client_id) do
    Phoenix.ChannelTest.socket(CachePuppyCoreWeb.UserSocket, "usersocket:#{client_id}", %{
      client_id: client_id
    })
  end
end
