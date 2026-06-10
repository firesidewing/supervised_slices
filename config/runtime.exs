import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/supervised_slices start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if stripe_secret_key = System.get_env("STRIPE_SECRET_KEY") do
  config :stripity_stripe, api_key: stripe_secret_key
end

if anthropic_api_key = System.get_env("ANTHROPIC_API_KEY") do
  config :supervised_slices, :anthropic_api_key, anthropic_api_key
end

config :supervised_slices, :posthog,
  api_key: System.get_env("POSTHOG_API_KEY"),
  host: System.get_env("POSTHOG_HOST", "https://us.i.posthog.com")

config :supervised_slices, :stripe,
  webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET", "whsec_placeholder"),
  price_id_basic: System.get_env("STRIPE_PRICE_ID_BASIC", "price_basic_placeholder"),
  price_id_pro: System.get_env("STRIPE_PRICE_ID_PRO", "price_pro_placeholder"),
  price_id_menu_upload:
    System.get_env("STRIPE_PRICE_ID_MENU_UPLOAD", "price_menu_upload_placeholder")

config :ex_aws,
  access_key_id: System.get_env("TIGRIS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("TIGRIS_SECRET_ACCESS_KEY"),
  s3: [
    scheme: "https://",
    host: "fly.storage.tigris.dev",
    region: "auto"
  ]

config :supervised_slices, :tigris_bucket, System.get_env("TIGRIS_BUCKET", "supervised-slices")

if System.get_env("PHX_SERVER") do
  config :supervised_slices, SupervisedSlicesWeb.Endpoint, server: true
end

config :supervised_slices, SupervisedSlicesWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  config :tzdata, :autoupdate, :disabled

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :supervised_slices, SupervisedSlices.Repo,
    ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
    prepare: :unnamed,
    connect_timeout: 15_000,
    timeout: 30_000,
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :supervised_slices, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :supervised_slices, SupervisedSlicesWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :supervised_slices,
    token_signing_secret:
      System.get_env("TOKEN_SIGNING_SECRET") ||
        raise("Missing environment variable `TOKEN_SIGNING_SECRET`!")

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :supervised_slices, SupervisedSlicesWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :supervised_slices, SupervisedSlicesWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :supervised_slices, SupervisedSlices.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For other adapters, see the Swoosh documentation:
  # https://hexdocs.pm/swoosh/Swoosh.html#module-installation

  if resend_api_key = System.get_env("RESEND_API_KEY") do
    config :supervised_slices, SupervisedSlices.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: resend_api_key
  end
end
