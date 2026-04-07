defmodule BeamlineCoreAppWeb.EventChannel do
  use BeamlineCoreAppWeb, :channel

  @impl true
  def join("events:" <> topic, _payload, socket) do
    {:ok, assign(socket, :topic, topic)}
  end

  @impl true
  def handle_in(
        "publish",
        %{"event" => event, "payload" => payload},
        %{assigns: %{topic: topic, client_id: client_id}} = socket
      ) do
    message = %{
      "v" => 1,
      "type" => "publish",
      "topic" => topic,
      "event" => event,
      "payload" => payload,
      "ts" => System.system_time(:millisecond),
      "meta" => %{"clientId" => client_id}
    }

    broadcast!(socket, "message", message)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("message", %{"type" => "publish"} = envelope, socket) do
    event = Map.get(envelope, "event")
    payload = Map.get(envelope, "payload")
    client_id = socket.assigns.client_id

    message = %{
      "v" => 1,
      "type" => "publish",
      "topic" => socket.assigns.topic,
      "event" => event,
      "payload" => payload,
      "ts" => System.system_time(:millisecond),
      "meta" => %{"clientId" => client_id}
    }

    broadcast!(socket, "message", message)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "unsupported_event"}}, socket}
  end
end
