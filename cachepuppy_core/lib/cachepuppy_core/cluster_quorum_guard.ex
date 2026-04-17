defmodule CachePuppyCore.ClusterQuorumGuard do
  @moduledoc false

  use GenServer
  require Logger

  alias CachePuppyCore.CacheConfig

  @mode_key {__MODULE__, :mode}
  @snapshot_blocked_key {__MODULE__, :snapshot_blocked}

  @type mode :: :healthy | :grace | :fenced

  defmodule State do
    @moduledoc false
    @enforce_keys [:poll_interval_ms, :grace_ms]
    defstruct mode: :healthy,
              poll_interval_ms: 2_000,
              grace_ms: 20_000,
              grace_deadline_ms: nil
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec snapshot_blocked?() :: boolean()
  def snapshot_blocked? do
    :persistent_term.get(@snapshot_blocked_key, false)
  end

  @spec mode() :: mode()
  def mode do
    :persistent_term.get(@mode_key, :healthy)
  end

  @spec quorum_status() :: %{current_nodes: pos_integer(), quorum_threshold: pos_integer(), quorum_met: boolean()}
  def quorum_status do
    total_nodes = CacheConfig.expected_nodes()
    quorum_threshold = div(total_nodes, 2) + 1
    current_nodes = length(Node.list()) + 1
    %{current_nodes: current_nodes, quorum_threshold: quorum_threshold, quorum_met: current_nodes >= quorum_threshold}
  end

  @impl true
  def init(_opts) do
    state = %State{
      poll_interval_ms: CacheConfig.quorum_poll_interval_ms(),
      grace_ms: CacheConfig.quorum_grace_ms()
    }

    state = transition(state, quorum_status())
    {:ok, schedule_tick(state)}
  end

  @impl true
  def handle_info(:quorum_tick, state) do
    state = transition(%{state | grace_deadline_ms: state.grace_deadline_ms}, quorum_status())
    {:noreply, schedule_tick(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp schedule_tick(state) do
    _ = Process.send_after(self(), :quorum_tick, state.poll_interval_ms)
    state
  end

  defp transition(state, %{quorum_met: true}) do
    case state.mode do
      :healthy ->
        publish_state(:healthy, false)
        %{state | mode: :healthy, grace_deadline_ms: nil}

      :grace ->
        Logger.warning("quorum_restored node=#{node()}")
        publish_state(:healthy, false)
        %{state | mode: :healthy, grace_deadline_ms: nil}

      :fenced ->
        state
    end
  end

  defp transition(state, %{quorum_met: false} = status) do
    now_ms = System.system_time(:millisecond)

    case state.mode do
      :healthy ->
        deadline = now_ms + state.grace_ms

        Logger.warning(
          "quorum_lost_enter_grace node=#{node()} current_nodes=#{status.current_nodes} quorum_threshold=#{status.quorum_threshold} grace_ms=#{state.grace_ms}"
        )

        publish_state(:grace, true)
        %{state | mode: :grace, grace_deadline_ms: deadline}

      :grace ->
        if now_ms >= (state.grace_deadline_ms || now_ms) do
          Logger.error(
            "quorum_grace_expired_node_stopping node=#{node()} current_nodes=#{status.current_nodes} quorum_threshold=#{status.quorum_threshold}"
          )

          publish_state(:fenced, true)

          if CacheConfig.quorum_stop_enabled?() do
            _ = Task.start(fn -> System.stop(1) end)
          end

          %{state | mode: :fenced, grace_deadline_ms: state.grace_deadline_ms}
        else
          publish_state(:grace, true)
          %{state | mode: :grace}
        end

      :fenced ->
        publish_state(:fenced, true)
        state
    end
  end

  defp publish_state(mode, snapshot_blocked) do
    :persistent_term.put(@mode_key, mode)
    :persistent_term.put(@snapshot_blocked_key, snapshot_blocked)
  end
end
