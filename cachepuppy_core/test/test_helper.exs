# Run test modules serially: several suites mutate shared process-global state
# (`Application` env, Horde, `:persistent_term` quorum mode) that must not
# interleave with other cases.
ExUnit.start(max_cases: 1)
