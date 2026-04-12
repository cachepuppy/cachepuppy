defmodule CachePuppyCore.TopicProcess do
  @moduledoc false

  use GenServer

  require Logger

  defmodule State do
    @moduledoc false
    defstruct topic: nil,
              data: %{},
              idle_timeout_ms: 60_000,
              timer_ref: nil,
              webhook: nil,
              webhook_tick_ref: nil,
              dirty: false
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

  def configure_webhook(topic, opts) when is_map(opts),
    do: GenServer.call(via_topic(topic), {:configure_webhook, opts})

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
    if payload == state.data do
      {:reply, {:ok, state.data, false}, reset_idle_timer(state)}
    else
      dirty = state.webhook != nil
      state = %{state | data: payload, dirty: dirty} |> reset_idle_timer()
      {:reply, {:ok, state.data, true}, state}
    end
  end

  def handle_call({:set_state, payload}, _from, state) when not is_map(payload) do
    {:reply, {:error, :invalid_payload}, state}
  end

  @impl true
  def handle_call({:configure_webhook, opts}, _from, state) when is_map(opts) do
    cond do
      Map.get(opts, "flush") == false ->
        state = cancel_webhook_tick(state)
        {:reply, :ok, reset_idle_timer(%{state | webhook: nil, dirty: false})}

      Map.get(opts, "flush") == true ->
        case parse_webhook(opts) do
          {:ok, webhook} ->
            state = cancel_webhook_tick(state)
            state = %{state | webhook: webhook}
            {:reply, :ok, reset_idle_timer(schedule_webhook_tick(state))}

          {:error, reason} ->
            {:reply, {:error, reason}, reset_idle_timer(state)}
        end

      true ->
        {:reply, {:error, :invalid_webhook_config}, reset_idle_timer(state)}
    end
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

  @impl true
  def handle_info(:webhook_tick, state) do
    state = %{state | webhook_tick_ref: nil}

    state =
      if state.webhook && state.dirty do
        run_webhook_post_async(state)
        %{state | dirty: false}
      else
        state
      end

    state =
      if state.webhook do
        schedule_webhook_tick(state)
      else
        state
      end

    {:noreply, reset_idle_timer(state)}
  end

  defp parse_webhook(opts) do
    url =
      case Map.get(opts, "url") do
        u when is_binary(u) -> String.trim(u)
        _ -> nil
      end

    freq_sec =
      case Map.get(opts, "frequency") do
        n when is_integer(n) and n > 0 -> min(max(n, 1), 3600)
        n when is_float(n) and n > 0 -> min(max(trunc(n), 1), 3600)
        _ -> 10
      end

    if url && valid_webhook_url?(url) do
      {:ok, %{url: url, interval_ms: freq_sec * 1000}}
    else
      {:error, :invalid_webhook_config}
    end
  end

  defp valid_webhook_url?(url) when is_binary(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] && uri.host not in [nil, ""]
  end

  defp valid_webhook_url?(_), do: false

  defp schedule_webhook_tick(%State{webhook: nil} = state), do: state

  defp schedule_webhook_tick(%State{webhook: w} = state) do
    ref = Process.send_after(self(), :webhook_tick, w.interval_ms)
    %{state | webhook_tick_ref: ref}
  end

  defp cancel_webhook_tick(state) do
    %{state | webhook_tick_ref: cancel_timer_ref(state.webhook_tick_ref)}
  end

  defp run_webhook_post_async(%State{webhook: nil} = state), do: state

  defp run_webhook_post_async(state) do
    cfg = state.webhook
    topic = state.topic
    data = state.data
    now_ms = System.system_time(:millisecond)

    body = %{
      "topic" => topic,
      "state" => data,
      "ts" => now_ms
    }

    url = cfg.url

    _ =
      Task.start(fn ->
        case Req.post(url,
               finch: CachePuppyCore.Finch,
               json: body,
               headers: [{"content-type", "application/json"}],
               receive_timeout: 15_000
             ) do
          {:ok, %{status: s}} when s >= 200 and s < 300 ->
            :ok

          {:ok, %{status: s}} ->
            Logger.warning("TopicProcess webhook non-success status=#{s} topic=#{inspect(topic)}")

          {:error, reason} ->
            Logger.warning(
              "TopicProcess webhook failed topic=#{inspect(topic)} reason=#{inspect(reason)}"
            )
        end
      end)

    state
  end

  defp cancel_timer_ref(nil), do: nil

  defp cancel_timer_ref(ref) do
    Process.cancel_timer(ref)
    nil
  end

  defp reset_idle_timer(%State{idle_timeout_ms: timeout_ms, timer_ref: old_ref} = state) do
    if old_ref, do: Process.cancel_timer(old_ref)
    ref = Process.send_after(self(), :idle_timeout, timeout_ms)
    %{state | timer_ref: ref}
  end

  defp via_topic(topic), do: {:via, Horde.Registry, {CachePuppyCore.TopicRegistry, topic}}
end
