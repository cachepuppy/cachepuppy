defmodule CachePuppyCore.TopicProcess do
  @moduledoc false

  use GenServer

  defmodule State do
    @moduledoc false
    defstruct topic: nil, data: %{}, idle_timeout_ms: 60_000, timer_ref: nil
  end

  def child_spec(opts) do
    topic = Keyword.fetch!(opts, :topic)

    %{
      id: {__MODULE__, topic},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def start_link(opts) do
    topic = Keyword.fetch!(opts, :topic)
    GenServer.start_link(__MODULE__, opts, name: via_topic(topic))
  end

  def set_state(topic, payload), do: GenServer.call(via_topic(topic), {:set_state, payload})
  def get_state(topic), do: GenServer.call(via_topic(topic), :get_state)
  def touch(topic), do: GenServer.cast(via_topic(topic), :touch)
  def close(topic), do: GenServer.stop(via_topic(topic), :normal)

  @impl true
  def init(opts) do
    topic = Keyword.fetch!(opts, :topic)
    idle_timeout_ms = Keyword.fetch!(opts, :idle_timeout_ms)
    state = %State{topic: topic, idle_timeout_ms: idle_timeout_ms}
    {:ok, reset_idle_timer(state)}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state.data}, reset_idle_timer(state)}
  end

  @impl true
  def handle_call({:set_state, payload}, _from, state) when is_map(payload) do
    new_state = %{state | data: payload} |> reset_idle_timer()
    {:reply, {:ok, new_state.data}, new_state}
  end

  def handle_call({:set_state, _payload}, _from, state) do
    {:reply, {:error, :invalid_payload}, state}
  end

  @impl true
  def handle_cast(:touch, state) do
    {:noreply, reset_idle_timer(state)}
  end

  @impl true
  def handle_info(:idle_timeout, state) do
    case Horde.Registry.lookup(CachePuppyCore.TopicRegistry, state.topic) do
      [{pid, _}] when pid == self() -> {:stop, :normal, state}
      _ -> {:noreply, reset_idle_timer(state)}
    end
  end

  defp reset_idle_timer(%State{idle_timeout_ms: timeout_ms, timer_ref: old_ref} = state) do
    if old_ref, do: Process.cancel_timer(old_ref)
    ref = Process.send_after(self(), :idle_timeout, timeout_ms)
    %{state | timer_ref: ref}
  end

  defp via_topic(topic), do: {:via, Horde.Registry, {CachePuppyCore.TopicRegistry, topic}}
end
