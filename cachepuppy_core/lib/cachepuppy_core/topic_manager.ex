defmodule CachePuppyCore.TopicManager do
  @moduledoc false

  alias CachePuppyCore.TopicProcess

  @default_idle_timeout_ms 60_000

  def ensure_started(topic) when is_binary(topic) do
    case Horde.Registry.lookup(CachePuppyCore.TopicRegistry, topic) do
      [{pid, _}] -> {:ok, pid}
      [] -> start_topic(topic)
    end
  end

  def set_state(topic, payload) when is_binary(topic) do
    with {:ok, _pid} <- ensure_started(topic),
         {:ok, data, changed?} <- TopicProcess.set_state(topic, payload) do
      {:ok, data, changed?}
    end
  end

  def configure_topic_webhook(topic, opts) when is_binary(topic) and is_map(opts) do
    with {:ok, _pid} <- ensure_started(topic) do
      TopicProcess.configure_webhook(topic, opts)
    end
  end

  def get_state(topic) when is_binary(topic) do
    case Horde.Registry.lookup(CachePuppyCore.TopicRegistry, topic) do
      [{pid, _}] ->
        case TopicProcess.get_state(topic) do
          {:ok, state} -> {:ok, state, to_string(node(pid))}
          {:error, reason} -> {:error, reason}
        end

      [] ->
        {:error, :topic_not_found}
    end
  end

  def touch(topic) when is_binary(topic) do
    with {:ok, _pid} <- ensure_started(topic) do
      TopicProcess.touch(topic)
      :ok
    end
  end

  def notify_activity(topic) when is_binary(topic) do
    case Horde.Registry.lookup(CachePuppyCore.TopicRegistry, topic) do
      [{_pid, _}] ->
        TopicProcess.touch(topic)
        :ok

      [] ->
        :ok
    end
  end

  def close_topic(topic) when is_binary(topic) do
    case Horde.Registry.lookup(CachePuppyCore.TopicRegistry, topic) do
      [{pid, _}] ->
        Horde.DynamicSupervisor.terminate_child(CachePuppyCore.TopicSupervisor, pid)

      [] ->
        {:error, :topic_not_found}
    end
  end

  defp start_topic(topic) do
    child_spec = {TopicProcess, topic: topic, idle_timeout_ms: idle_timeout_ms()}

    case Horde.DynamicSupervisor.start_child(CachePuppyCore.TopicSupervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp idle_timeout_ms do
    Application.get_env(:cachepuppy_core, :topic_idle_timeout_ms, @default_idle_timeout_ms)
  end
end
