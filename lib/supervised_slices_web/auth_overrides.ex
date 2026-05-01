defmodule SupervisedSlicesWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  # configure your UI overrides here

  # First argument to `override` is the component name you are overriding.
  # The body contains any number of configurations you wish to override
  # Below are some examples

  # For a complete reference, see https://hexdocs.pm/ash_authentication_phoenix/ui-overrides.html

  override AshAuthentication.Phoenix.SignInLive do
    set :root_class, "grid min-h-dvh place-items-center bg-surface bg-paper p-4 sm:p-6 lg:p-8"
  end

  override AshAuthentication.Phoenix.RegisterLive do
    set :root_class, "grid min-h-dvh place-items-center bg-surface bg-paper p-4 sm:p-6 lg:p-8"
  end

  override AshAuthentication.Phoenix.ResetLive do
    set :root_class, "grid min-h-dvh place-items-center bg-surface bg-paper p-4 sm:p-6 lg:p-8"
  end

  override AshAuthentication.Phoenix.VerifyLive do
    set :root_class, "grid min-h-dvh place-items-center bg-surface bg-paper p-4 sm:p-6 lg:p-8"
  end

  override AshAuthentication.Phoenix.MagicSignInLive do
    set :root_class, "grid min-h-dvh place-items-center bg-surface bg-paper p-4 sm:p-6 lg:p-8"
  end

  override AshAuthentication.Phoenix.Components.SignIn do
    set :root_class, "mx-auto w-full max-w-md auth-card border-0"
    set :strategy_class, "w-full"
    set :authentication_error_container_class, "text-error text-center mb-4"
    set :show_banner, true
  end

  override AshAuthentication.Phoenix.Components.Register do
    set :root_class, "mx-auto w-full max-w-md auth-card border-0"
    set :show_banner, true
  end

  override AshAuthentication.Phoenix.Components.Banner do
    set :show_banner, true
    set :root_class, "w-full flex flex-col items-center justify-center pt-8 pb-12"
    set :image_url, "/images/chit.webp"
    set :dark_image_url, "/images/chit.webp"
    set :image_class, "size-28 object-contain mb-8 dark:hidden"
    set :dark_image_class, "size-28 object-contain mb-8 hidden dark:block"
    set :text, nil

    set :text_class,
        "font-headline font-black text-4xl tracking-tighter uppercase text-on-surface text-center"
  end

  override AshAuthentication.Phoenix.Components.Footer do
    set :show_footer, false
  end

  override AshAuthentication.Phoenix.Components.Password do
    set :register_extra_component, &SupervisedSlicesWeb.AuthComponents.RegisterExtra.render/1
    set :sign_in_toggle_text, "Already have an account? Sign in"
    set :register_toggle_text, "New here? Register your kitchen"
    set :reset_toggle_text, "Lost your recipe? Reset password"

    set :interstitial_class, "flex flex-col gap-4 mt-12 w-full"

    set :toggler_class,
        "text-primary hover:text-primary-container font-bold uppercase tracking-[0.15em] text-[11px] py-4 px-6 rounded-md bg-surface-container-low transition-all inline-block w-full text-center"
  end

  override AshAuthentication.Phoenix.Components.Password.SignInForm do
    set :label_class,
        "font-headline text-lg font-bold uppercase tracking-tight text-on-surface/40 mb-10 text-center"

    set :button_text, "SIGN IN"
  end

  override AshAuthentication.Phoenix.Components.Password.RegisterForm do
    set :label_class,
        "font-headline text-lg font-bold uppercase tracking-tight text-on-surface/40 mb-10 text-center"

    set :button_text, "CREATE YOUR ACCOUNT"
  end

  override AshAuthentication.Phoenix.Components.Password.ResetForm do
    set :label_class,
        "font-headline text-lg font-bold uppercase tracking-tight text-on-surface/40 mb-10 text-center"

    set :button_text, "RESET YOUR PASSWORD"
  end

  override AshAuthentication.Phoenix.Components.Password.RequestResetForm do
    set :label_class,
        "font-headline text-lg font-bold uppercase tracking-tight text-on-surface/40 mb-10 text-center"

    set :button_text, "SEND RESET RECIPE"
  end

  override AshAuthentication.Phoenix.Components.Password.Input do
    set :field_class, "mb-8 last:mb-0"

    set :label_class,
        "font-label text-[10px] font-bold uppercase tracking-[0.2em] text-on-surface-variant/60 mb-2 ml-1"

    set :input_class,
        "w-full bg-transparent border-0 border-b border-outline-variant/30 rounded-none h-12 px-0 focus:outline-none focus:ring-0 focus:border-primary focus:border-b-2 transition-all font-medium text-on-surface text-lg placeholder:text-on-surface/20"

    set :input_class_with_error,
        "w-full bg-transparent border-0 border-b border-error/50 rounded-none h-12 px-0 focus:outline-none focus:ring-0 focus:border-error focus:border-b-2 transition-all font-medium text-on-surface text-lg placeholder:text-on-surface/20"

    set :submit_class, "btn btn-tomato w-full h-14 rounded-md mt-10"
  end

  # override AshAuthentication.Phoenix.Components.Banner do
  #   set :image_url, "https://media.giphy.com/media/g7GKcSzwQfugw/giphy.gif"
  #   set :text_class, "bg-red-500"
  # end

  # override AshAuthentication.Phoenix.Components.SignIn do
  #  set :show_banner, false
  # end
end
