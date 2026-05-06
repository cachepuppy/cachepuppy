defmodule CachePuppyCore.Persistence.CacheEntry do
  @moduledoc false

  @enforce_keys [:value]
  defstruct [:value, :expires_at_ms]

  @type t :: %__MODULE__{value: term(), expires_at_ms: pos_integer() | nil}

  @spec from_wal(term(), integer(), nil | pos_integer()) :: t()
  def from_wal(value, wal_ts_ms, nil) when is_integer(wal_ts_ms) do
    %__MODULE__{value: value, expires_at_ms: nil}
  end

  def from_wal(value, wal_ts_ms, ttl_ms)
      when is_integer(wal_ts_ms) and is_integer(ttl_ms) and ttl_ms > 0 do
    %__MODULE__{value: value, expires_at_ms: wal_ts_ms + ttl_ms}
  end
end
