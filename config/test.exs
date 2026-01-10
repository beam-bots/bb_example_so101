# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

import Config

# Don't start the robot during tests
config :bb_example_so101, start_robot: false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bb_example_so101, BB.Example.SO101Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "fo2Jgh6mMmMqvXI9+5x2VPP5Ya19f5YvOARKW85bWd/A4MJ4NIm1942kG5FOyyoc",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
