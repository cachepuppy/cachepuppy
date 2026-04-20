defmodule CachePuppyCoreWeb.EventChannel do
  use CachePuppyCoreWeb, :channel
  alias CachePuppyCore.TopicManager
  alias CachePuppyCoreWeb.Presence
  alias CachePuppyCoreWeb.TopicRoom

  intercept ["message"]

  @impl true
  def join("events:" <> topic, _payload, %{assigns: %{client_id: client_id}} = socket) do
    {:ok, _pid} = TopicManager.ensure_started(topic)
    socket = assign(socket, :topic, topic)

    case Presence.track(socket, client_id, %{online_at: System.system_time(:second)}) do
      {:ok, _} ->
        # After join completes, push a full snapshot (push/3 is not allowed inside join/3 on Phoenix 1.8+).
        send(self(), :presence_snapshot)
        {:ok, %{"connected_node" => to_string(node())}, socket}

      {:error, reason} ->
        {:error, %{reason: "presence_track_failed", detail: inspect(reason)}}
    end
  end

  @impl true
  def handle_info(:presence_snapshot, socket) do
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  @impl true
  def handle_in(
        "publish",
        %{"event" => event, "payload" => payload},
        %{assigns: %{topic: topic, client_id: client_id}} = socket
      ) do
    message = TopicRoom.build_publish(topic, event, payload, client_id)
    TopicRoom.broadcast_message!(topic, message)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("message", %{"type" => "publish"} = envelope, socket) do
    event = Map.get(envelope, "event")
    payload = Map.get(envelope, "payload")
    client_id = socket.assigns.client_id

    message = TopicRoom.build_publish(socket.assigns.topic, event, payload, client_id)
    TopicRoom.broadcast_message!(socket.assigns.topic, message)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("set_state", %{"payload" => payload}, %{assigns: %{topic: topic}} = socket)
      when is_map(payload) do
    case TopicManager.set_state(topic, payload) do
      {:ok, state, true} ->
        TopicRoom.broadcast_state_updated!(topic, state)
        {:reply, {:ok, %{"state" => state}}, socket}

      {:ok, state, false} ->
        {:reply, {:ok, %{"state" => state}}, socket}

      {:error, :invalid_payload} ->
        {:reply, {:error, %{reason: "invalid_payload"}}, socket}

      {:error, _reason} ->
        {:reply, {:error, %{reason: "state_update_failed"}}, socket}
    end
  end

  def handle_in("set_state", _body, socket) do
    {:reply, {:error, %{reason: "invalid_payload"}}, socket}
  end

  @impl true
  def handle_in("configure_topic_webhook", body, %{assigns: %{topic: topic}} = socket)
      when is_map(body) do
    case TopicManager.configure_topic_webhook(topic, body) do
      :ok ->
        {:reply, :ok, socket}

      {:error, :invalid_webhook_config} ->
        {:reply, {:error, %{reason: "invalid_webhook_config"}}, socket}

      {:error, _reason} ->
        {:reply, {:error, %{reason: "webhook_configure_failed"}}, socket}
    end
  end

  @impl true
  def handle_in("get_state", _payload, %{assigns: %{topic: topic}} = socket) do
    case TopicManager.get_state(topic) do
      {:ok, state, source_node} ->
        {:reply,
         {:ok,
          %{
            "state" => state,
            "meta" => %{
              "source_node" => source_node,
              "served_by_node" => to_string(node())
            }
          }}, socket}

      {:error, :topic_not_found} ->
        {:reply, {:error, %{reason: "topic_not_found"}}, socket}

      {:error, _reason} ->
        {:reply, {:error, %{reason: "state_fetch_failed"}}, socket}
    end
  end

  @impl true
  def handle_in("close_topic", _payload, %{assigns: %{topic: topic}} = socket) do
    case TopicManager.close_topic(topic) do
      :ok -> {:reply, {:ok, %{"closed" => true}}, socket}
      {:error, :topic_not_found} -> {:reply, {:ok, %{"closed" => false}}, socket}
      {:error, _reason} -> {:reply, {:error, %{reason: "close_topic_failed"}}, socket}
    end
  end

  @impl true
  def handle_in("client_count", _payload, socket) do
    count =
      socket
      |> Presence.list()
      |> map_size()

    {:reply, {:ok, %{"client_count" => count}}, socket}
  end

  @impl true
  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "unsupported_event"}}, socket}
  end

  @impl true
  def handle_out("message", payload, socket) do
    push(socket, "message", TopicRoom.put_served_by_node(payload))
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, %{assigns: %{topic: topic}}) do
    TopicManager.notify_activity(topic)
    :ok
  end
end
