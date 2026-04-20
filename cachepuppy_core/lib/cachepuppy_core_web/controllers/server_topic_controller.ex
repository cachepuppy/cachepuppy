defmodule CachePuppyCoreWeb.ServerTopicController do
  use CachePuppyCoreWeb, :controller

  alias CachePuppyCore.TopicManager
  alias CachePuppyCoreWeb.Presence
  alias CachePuppyCoreWeb.TopicRoom

  @server_client_id "server_api"

  def put_state(conn, %{"topic" => topic} = params) when is_binary(topic) do
    payload = Map.drop(params, ["topic"])

    if is_map(payload) do
      case TopicManager.set_state(topic, payload) do
        {:ok, state, true} ->
          TopicRoom.broadcast_state_updated!(topic, state)
          json(conn, %{"state" => state})

        {:ok, state, false} ->
          json(conn, %{"state" => state})

        {:error, :invalid_payload} ->
          conn |> put_status(:bad_request) |> json(%{reason: "invalid_payload"})

        {:error, _} ->
          conn |> put_status(:internal_server_error) |> json(%{reason: "state_update_failed"})
      end
    else
      bad_request(conn, "invalid_payload")
    end
  end

  def put_state(conn, _params), do: bad_request(conn, "invalid_payload")

  def get_state(conn, %{"topic" => topic}) when is_binary(topic) do
    case TopicManager.get_state(topic) do
      {:ok, state, source_node} ->
        json(conn, %{
          "state" => state,
          "meta" => %{
            "source_node" => source_node,
            "served_by_node" => to_string(node())
          }
        })

      {:error, :topic_not_found} ->
        conn |> put_status(:not_found) |> json(%{reason: "topic_not_found"})

      {:error, _} ->
        conn |> put_status(:internal_server_error) |> json(%{reason: "state_fetch_failed"})
    end
  end

  def get_state(conn, _params), do: bad_request(conn, "invalid_payload")

  def delete_topic(conn, %{"topic" => topic}) when is_binary(topic) do
    case TopicManager.close_topic(topic) do
      :ok ->
        json(conn, %{"closed" => true})

      {:ok, _} ->
        json(conn, %{"closed" => true})

      {:error, :topic_not_found} ->
        json(conn, %{"closed" => false})

      {:error, _} ->
        conn |> put_status(:internal_server_error) |> json(%{reason: "close_topic_failed"})
    end
  end

  def delete_topic(conn, _params), do: bad_request(conn, "invalid_payload")

  def post_message(conn, %{"topic" => topic} = params) when is_binary(topic) do
    case string_param(params, "event") do
      {:ok, event} ->
        payload = Map.get(params, "payload")
        envelope = TopicRoom.build_publish(topic, event, payload, @server_client_id)
        TopicRoom.broadcast_message!(topic, envelope)
        conn |> put_status(:accepted) |> json(%{"ok" => true})

      :error ->
        bad_request(conn, "invalid_payload")
    end
  end

  def post_message(conn, _params), do: bad_request(conn, "invalid_payload")

  def get_presence(conn, %{"topic" => topic}) when is_binary(topic) do
    list = Presence.list(TopicRoom.channel_topic(topic))

    json(conn, %{
      "client_count" => map_size(list),
      "presence" => list
    })
  end

  def get_presence(conn, _params), do: bad_request(conn, "invalid_payload")

  defp string_param(params, key) do
    case Map.get(params, key) do
      event when is_binary(event) and event != "" ->
        {:ok, event}

      _ ->
        :error
    end
  end

  defp bad_request(conn, reason) do
    conn |> put_status(:bad_request) |> json(%{reason: reason})
  end
end
