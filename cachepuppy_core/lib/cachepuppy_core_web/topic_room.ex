defmodule CachePuppyCoreWeb.TopicRoom do
  @moduledoc false

  alias CachePuppyCoreWeb.Endpoint

  @doc """
  Phoenix channel / Presence topic string for a logical room name (without `events:` prefix).
  """
  def channel_topic(logical_topic) when is_binary(logical_topic) do
    "events:" <> logical_topic
  end

  def build_publish(logical_topic, event, payload, client_id) when is_binary(logical_topic) do
    %{
      "v" => 1,
      "type" => "publish",
      "topic" => logical_topic,
      "event" => event,
      "payload" => payload,
      "ts" => System.system_time(:millisecond),
      "meta" => %{"clientId" => client_id, "source_node" => to_string(node())}
    }
  end

  def put_served_by_node(payload) when is_map(payload) do
    raw_meta = Map.get(payload, "meta")

    meta =
      if is_map(raw_meta) do
        Map.put(raw_meta, "served_by_node", to_string(node()))
      else
        %{"served_by_node" => to_string(node())}
      end

    Map.put(payload, "meta", meta)
  end

  @doc """
  Fan out an envelope to every subscriber on the room (same as `broadcast!(socket, "message", envelope)`).
  """
  def broadcast_message!(logical_topic, envelope)
      when is_binary(logical_topic) and is_map(envelope) do
    Endpoint.broadcast(channel_topic(logical_topic), "message", envelope)
    :ok
  end

  def broadcast_state_updated!(logical_topic, state) when is_binary(logical_topic) do
    envelope = build_publish(logical_topic, "state_updated", state, "topic_process")
    broadcast_message!(logical_topic, envelope)
  end
end
