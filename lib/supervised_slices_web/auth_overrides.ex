defmodule SupervisedSlicesWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  # configure your UI overrides here

  # First argument to `override` is the component name you are overriding.
  # The body contains any number of configurations you wish to override
  # Below are some examples

  # For a complete reference, see https://hexdocs.pm/ash_authentication_phoenix/ui-overrides.html

  alias AshAuthentication.Phoenix.Components

  override AshAuthentication.Phoenix.SignInLive do
    set :root_class, "grid min-h-dvh place-items-center bg-surface p-4 sm:p-6 lg:p-8"
  end

  override AshAuthentication.Phoenix.RegisterLive do
    set :root_class, "grid min-h-dvh place-items-center bg-surface p-4 sm:p-6 lg:p-8"
  end

  override Components.SignIn do
    set :root_class, "mx-auto w-full max-w-md auth-card border-0"
    set :strategy_class, "w-full"
    set :authentication_error_container_class, "text-error text-center mb-4"
  end

  override Components.Banner do
    set :show_banner, true
    set :root_class, "w-full flex flex-col items-center justify-center pt-2 pb-6 mb-4"
    set :image_url, "/images/logo.svg"
    set :dark_image_url, "/images/logo.svg"
    set :image_class, "size-20 rounded-2xl shadow-lg -rotate-3 mb-6"
    set :dark_image_class, "size-20 rounded-2xl shadow-lg -rotate-3 mb-6"
    set :text, "Supervised Slices"
    set :text_class, "font-headline font-black text-3xl tracking-tighter uppercase italic text-on-surface text-center"
  end

  override Components.Footer do
    set :show_footer, false
  end

  override Components.Password do
    set :register_extra_component, &SupervisedSlicesWeb.AuthComponents.RegisterExtra.render/1
    set :sign_in_toggle_text, "Already have an account? Sign in"
    set :register_toggle_text, "New here? Register your kitchen"
    set :reset_toggle_text, "Lost your recipe? Reset password"
    set :toggler_class, "text-primary hover:text-primary-container font-black uppercase tracking-widest text-[10px] py-3 px-6 rounded-full bg-primary/5 transition-all inline-block mt-8 w-full text-center"
  end

  override Components.Password.SignInForm do
    set :label_class, "font-headline text-lg font-black uppercase italic tracking-tight text-on-surface/40 mb-10 text-center"
    set :button_text, "SIGN IN TO KITCHEN"
  end

  override Components.Password.RegisterForm do
    set :label_class, "font-headline text-lg font-black uppercase italic tracking-tight text-on-surface/40 mb-10 text-center"
    set :button_text, "OPEN NEW KITCHEN"
  end

  override Components.Password.Input do
    set :field_class, "mb-6 last:mb-0"
    set :label_class, "font-headline text-[10px] font-black uppercase tracking-[0.2em] text-on-surface-variant/40 mb-2 ml-1"
    set :input_class, "bg-surface-container-low border-0 rounded-2xl h-16 px-6 focus:ring-4 focus:ring-primary/10 transition-all font-medium text-on-surface shadow-inner text-lg"
    set :input_class_with_error, "bg-surface-container-low border-2 border-error/20 rounded-2xl h-16 px-6 focus:ring-4 focus:ring-error/10 transition-all font-medium text-on-surface shadow-inner text-lg"
    set :submit_class, "btn btn-tomato w-full h-16 rounded-2xl mt-6"
  end

  # override AshAuthentication.Phoenix.Components.Banner do
  #   set :image_url, "https://media.giphy.com/media/g7GKcSzwQfugw/giphy.gif"
  #   set :text_class, "bg-red-500"
  # end

  # override AshAuthentication.Phoenix.Components.SignIn do
  #  set :show_banner, false
  # end
end
