defmodule BeamlineCoreAppWeb.Presence do
  use Phoenix.Presence,
    otp_app: :beamline_core_app,
    pubsub_server: BeamlineCoreApp.PubSub
end
