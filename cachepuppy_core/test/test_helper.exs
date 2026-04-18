# Run test modules serially: several suites mutate shared process-global state
# (`Application` env, Horde, `:persistent_term` quorum snapshot flags) that must
# not interleave with other cases (e.g. flush tests fence snapshots via PT while
# quorum tests assert on the same keys).
ExUnit.start(max_cases: 1)
