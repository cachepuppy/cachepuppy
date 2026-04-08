defmodule CachePuppyCoreWeb.Presence do
  use Phoenix.Presence,
    otp_app: :cachepuppy_core,
    pubsub_server: CachePuppyCore.PubSub
end
