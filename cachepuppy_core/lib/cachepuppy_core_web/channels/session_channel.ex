defmodule CachePuppyCoreWeb.SessionChannel do
  @moduledoc false

  use CachePuppyCoreWeb, :channel

  @impl true
  def join("session", _payload, %{assigns: %{client_id: client_id}} = socket) do
    socket = assign(socket, :session_state, %{})
    {:ok, %{"connected_node" => to_string(node()), "client_id" => client_id}, socket}
  end

  @impl true
  def handle_in("set_session_state", %{"payload" => payload}, socket) when is_map(payload) do
    socket = assign(socket, :session_state, payload)
    {:reply, {:ok, %{"state" => payload}}, socket}
  end

  @impl true
  def handle_in("set_session_state", %{"payload" => _payload}, socket) do
    {:reply, {:error, %{reason: "invalid_payload"}}, socket}
  end

  @impl true
  def handle_in("get_session_state", _payload, socket) do
    session_state = Map.get(socket.assigns, :session_state, %{})
    {:reply, {:ok, %{"state" => session_state}}, socket}
  end

  @impl true
  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "unsupported_event"}}, socket}
  end
end
