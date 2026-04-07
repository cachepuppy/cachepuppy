defmodule BeamlineCoreAppWeb.EventChannel do
  use BeamlineCoreAppWeb, :channel
  alias BeamlineCoreAppWeb.Presence

  @impl true
  def join("events:" <> topic, _payload, %{assigns: %{client_id: client_id}} = socket) do
    socket = assign(socket, :topic, topic)
    send(self(), {:track_presence, client_id})
    {:ok, socket}
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
  def handle_info({:track_presence, client_id}, socket) do
    {:ok, _} =
      Presence.track(socket, client_id, %{
        online_at: System.system_time(:second)
      })

    {:noreply, socket}
  end
end
