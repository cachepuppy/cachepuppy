defmodule CachePuppyCoreWeb.EventChannel do
  use CachePuppyCoreWeb, :channel
  alias CachePuppyCore.TopicManager
  alias CachePuppyCoreWeb.Presence

  intercept ["cachepuppy_targeted", "message"]

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
    message = build_publish(topic, event, payload, client_id)
    broadcast!(socket, "message", message)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("message", %{"type" => "publish"} = envelope, socket) do
    event = Map.get(envelope, "event")
    payload = Map.get(envelope, "payload")
    client_id = socket.assigns.client_id

    message = build_publish(socket.assigns.topic, event, payload, client_id)
    broadcast!(socket, "message", message)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in(
        "publish_to",
        %{"event" => event, "payload" => payload, "client_ids" => ids},
        %{assigns: %{topic: topic, client_id: client_id}} = socket
      )
      when is_list(ids) do
    target_ids = for id <- ids, is_binary(id), do: id

    broadcast_payload =
      build_publish(topic, event, payload, client_id)
      |> Map.put("_target_client_ids", target_ids)

    broadcast!(socket, "cachepuppy_targeted", broadcast_payload)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("set_state", %{"payload" => payload}, %{assigns: %{topic: topic}} = socket)
      when is_map(payload) do
    case TopicManager.set_state(topic, payload) do
      {:ok, state, true} ->
        broadcast_state_updated(socket, topic, state)
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
    push(socket, "message", put_served_by_node(payload))
    {:noreply, socket}
  end

  @impl true
  def handle_out("cachepuppy_targeted", payload, socket) do
    target_ids = Map.get(payload, "_target_client_ids", [])
    my_id = socket.assigns.client_id

    if my_id in target_ids do
      clean = Map.drop(payload, ["_target_client_ids"])
      push(socket, "message", put_served_by_node(clean))
    end

    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, %{assigns: %{topic: topic}}) do
    TopicManager.notify_activity(topic)
    :ok
  end

  defp broadcast_state_updated(socket, topic, state) do
    message = build_publish(topic, "state_updated", state, "topic_process")
    broadcast!(socket, "message", message)
  end

  defp build_publish(topic, event, payload, client_id) do
    %{
      "v" => 1,
      "type" => "publish",
      "topic" => topic,
      "event" => event,
      "payload" => payload,
      "ts" => System.system_time(:millisecond),
      "meta" => %{"clientId" => client_id, "source_node" => to_string(node())}
    }
  end

  defp put_served_by_node(payload) do
    raw_meta = Map.get(payload, "meta")

    meta =
      if is_map(raw_meta) do
        Map.put(raw_meta, "served_by_node", to_string(node()))
      else
        %{"served_by_node" => to_string(node())}
      end

    Map.put(payload, "meta", meta)
  end
end
