import Config
config :supervised_slices, Oban, testing: :manual
config :supervised_slices, token_signing_secret: "/aD9E3TZcnru788Hs6nnzyU6P4FvPMWp"
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :supervised_slices, SupervisedSlices.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "supervised_slices_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :supervised_slices, SupervisedSlicesWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "UTVWQb+7xfA5TTN6k6OfZdlKa1DsYw5HnRo8SUl/a+Zl9DF+GSRJPq7aLKeEXC5+",
  server: false

# In test we don't send emails
config :supervised_slices, SupervisedSlices.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

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

# Allow Req.Test stubs in GeofenceChecker during tests
config :supervised_slices, :req_options, plug: {Req.Test, :nominatim}
