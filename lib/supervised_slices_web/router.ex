defmodule SupervisedSlicesWeb.Router do
  use SupervisedSlicesWeb, :router

  import Oban.Web.Router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SupervisedSlicesWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
    plug SupervisedSlicesWeb.Plugs.GuestSession
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", SupervisedSlicesWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes,
      on_mount: [SupervisedSlicesWeb.AshScopeHook] do
      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {SupervisedSlicesWeb.LiveUserAuth, :live_no_user}

      live "/menu/:org_slug", MenuLive, :index
      live "/menu/:org_slug/item/:id", MenuLive, :show

      live "/orders/:org_slug/:order_id", OrderTrackingLive, :index

      # Billing flow — requires auth; org loaded from :org_slug by AshScopeHook
      live "/billing/setup/:org_slug", BillingLive.Setup, :index
      live "/billing/success/:org_slug", BillingLive.Success, :index

      live "/kitchen/:org_slug", AdminLive, :orders
      live "/kitchen/:org_slug/baskets", AdminLive, :baskets
      live "/kitchen/:org_slug/history", AdminLive, :history
      live "/kitchen/:org_slug/menu", AdminLive, :menu
      live "/kitchen/:org_slug/settings", AdminLive, :settings
    end
  end

  # Stripe webhooks — no CSRF, raw body preserved for signature verification
  scope "/webhooks", SupervisedSlicesWeb do
    pipe_through :api
    post "/stripe", StripeWebhookController, :event
  end

  scope "/", SupervisedSlicesWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Stripe Customer Portal redirect (requires browser session for auth)
    get "/billing/manage/:org_slug", BillingController, :portal

    auth_routes AuthController, SupervisedSlices.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{SupervisedSlicesWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    SupervisedSlicesWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  SupervisedSlicesWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route SupervisedSlices.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [
        SupervisedSlicesWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(SupervisedSlices.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [
        SupervisedSlicesWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", SupervisedSlicesWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:supervised_slices, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SupervisedSlicesWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/" do
      pipe_through :browser

      oban_dashboard("/oban")
    end
  end

  if Application.compile_env(:supervised_slices, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
