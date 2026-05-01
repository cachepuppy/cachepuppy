defmodule CachePuppyCore.RehydrationLog do
  @moduledoc false

  require Logger

  @mark "### CACHE-REHYDRATE ###"
  @edge String.duplicate("=", 72)

  @doc """
  High-visibility, multi-line log for Docker/grep (`docker logs ... | grep CACHE-REHYDRATE`).
  """
  @spec line(String.t()) :: :ok
  def line(detail) when is_binary(detail) do
    Logger.info(@edge)
    Logger.info("#{@mark} #{detail}")
    Logger.info(@edge)
    :ok
  end

  @doc """
  Same marker, one line (e.g. coordinator follow-up after a full `line/1` banner).
  """
  @spec single_line(String.t()) :: :ok
  def single_line(detail) when is_binary(detail) do
    Logger.info("#{@mark} #{detail}")
    :ok
  end

  @spec warning(String.t()) :: :ok
  def warning(detail) when is_binary(detail) do
    Logger.warning("#{@mark} #{detail}")
    :ok
  end
end
