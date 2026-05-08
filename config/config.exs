# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :ex_cldr, default_backend: SupervisedSlices.Cldr
config :ex_money, default_currency: :CAD
config :ash_money, default_currency: :CAD
config :ash_oban, pro?: false

config :supervised_slices, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10, cart_cleanup: 5, menu_uploads: 5, order_place_order: 5, trial_expiry: 5],
  repo: SupervisedSlices.Repo,
  plugins: [{Oban.Plugins.Cron, []}]

config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec, AshMoney.Types.Money],
  custom_types: [money: AshMoney.Types.Money]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :admin,
        :authentication,
        :token,
        :user_identity,
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [
      section_order: [:admin, :resources, :policies, :authorization, :domain, :execution]
    ]
  ]

config :supervised_slices,
  ecto_repos: [SupervisedSlices.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [
    SupervisedSlices.Accounts,
    SupervisedSlices.Orgs,
    SupervisedSlices.Menu,
    SupervisedSlices.Cart,
    SupervisedSlices.Orders
  ]

# Configure the endpoint
config :supervised_slices, SupervisedSlicesWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SupervisedSlicesWeb.ErrorHTML, json: SupervisedSlicesWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SupervisedSlices.PubSub,
  live_view: [signing_salt: "IFtJHXXY"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :supervised_slices, SupervisedSlices.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  supervised_slices: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  supervised_slices: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# OpenTelemetry — resource attributes stamped on every span
config :opentelemetry, :resource, service: [name: "Chitline", version: "0.1.0"]

config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp

# PromEx metrics (Prometheus endpoint on port 9568, separate from Phoenix)
config :supervised_slices, SupervisedSlices.PromEx,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :trace_id, :span_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :stripity_stripe, api_key: System.get_env("STRIPE_SECRET_KEY", "sk_test_placeholder")

config :supervised_slices, :vapid,
  public_key:
    "BM5Xgt6mnKHmtNOinlRSnh3KZ_0Ce_a5fGr8yMllSBFx9FmPd2V00Kdr5RhCgh3-33NVan6Eg4ydfJWl4LKUlgo",
  private_key: "xxQWv3c1HWTx-KG-Y8apdTsCCQW6FEdwpCNfvTwMTqE",
  subject: "mailto:support@chitline.com"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
