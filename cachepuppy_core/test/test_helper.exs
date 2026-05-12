# Run test modules serially: several suites mutate shared process-global state
# (`Application` env and Horde) that must not interleave with other cases.
ExUnit.start(max_cases: 1)
