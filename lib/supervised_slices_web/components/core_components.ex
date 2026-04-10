defmodule SupervisedSlicesWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: SupervisedSlicesWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(SupervisedSlicesWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(SupervisedSlicesWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  attr :cart, :any, required: true
  attr :show, :boolean, required: true
  attr :checkout_step, :atom, required: true
  attr :tax_rate, :any, required: true
  attr :org, :any, required: true

  def basket_drawer(assigns) do
    ~H"""
    <div
      id="basket-wrapper"
      class={[
        "fixed inset-0 z-50 transition-all duration-300",
        if(@show, do: "visible", else: "invisible pointer-events-none")
      ]}
    >
      <div
        id="basket-backdrop"
        class={[
          "absolute inset-0 bg-black/40 transition-opacity duration-300",
          if(@show, do: "opacity-100", else: "opacity-0")
        ]}
        phx-click={close_basket_js() |> JS.push("toggle_basket")}
      />
      <div
        id="basket-panel"
        class={[
          "absolute bottom-0 md:top-0 left-0 right-0 md:left-auto md:w-[480px] bg-background rounded-t-[3rem] md:rounded-l-[3.5rem] md:rounded-tr-none max-h-[90vh] md:max-h-screen flex flex-col transition-transform duration-500 ease-[cubic-bezier(0.34,1.56,0.64,1)]",
          "shadow-[0px_-16px_48px_rgba(0,0,0,0.15)] md:shadow-[-24px_0px_64px_rgba(0,0,0,0.1)]",
          if(@show, do: "translate-y-0 md:translate-x-0", else: "translate-y-full md:translate-x-full")
        ]}
      >
        <div class="flex items-center justify-between px-6 py-4 shrink-0 border-b border-on-surface/[0.03]">
          <div class="flex items-center gap-3">
            <button
              :if={@checkout_step == :confirm}
              phx-click="start_checkout"
              phx-value-step="review"
              class="w-11 h-11 flex items-center justify-center rounded-full bg-surface-container-low hover:bg-surface-container transition-all active:scale-90"
            >
              <span class="material-symbols-outlined font-black">arrow_back</span>
            </button>
            <div class="flex flex-col">
              <h2 class="font-headline text-2xl font-black tracking-tighter text-on-surface uppercase italic">
                {if @checkout_step == :confirm, do: "Your Details", else: "Your Basket"}
              </h2>
            </div>
          </div>
          <button
            phx-click={close_basket_js() |> JS.push("toggle_basket")}
            class="w-11 h-11 flex items-center justify-center rounded-full bg-surface-container-low hover:bg-surface-container transition-all active:scale-90"
          >
            <span class="material-symbols-outlined font-black">close</span>
          </button>
        </div>

        <%= if @checkout_step == :review do %>
          <div class="overflow-y-auto flex-1 px-4 py-4 scroll-smooth no-scrollbar">
            <%= if is_nil(@cart) or Enum.empty?(@cart.cart_items) do %>
              <div class="text-center py-24 text-on-surface-variant flex flex-col items-center">
                <div class="w-24 h-24 rounded-full bg-surface-container-low flex items-center justify-center mb-6">
                  <span class="material-symbols-outlined opacity-30 !text-5xl">shopping_cart</span>
                </div>
                <p class="text-xl font-black tracking-tight text-on-surface uppercase opacity-50">Empty Kitchen</p>
                <p class="mt-2 font-medium opacity-60">Add some slices to your tray</p>
              </div>
            <% else %>
              <div class="grid grid-cols-1 gap-3">
                <%= for item <- @cart.cart_items do %>
                  <% modifiers = basket_find_modifiers(item) %>
                  <div class="flex items-start justify-between p-3 bg-surface-container-lowest rounded-xl shadow-sm border border-on-surface/[0.03] gap-4 group hover:shadow-md transition-all duration-300">
                    <div class="flex-1 min-w-0 flex flex-col gap-1">
                      <div class="flex items-center gap-2">
                         <span :if={item.selected_size} class="text-[10px] font-black bg-secondary/10 text-secondary px-2 py-0.5 rounded-md uppercase tracking-widest">
                          {item.selected_size.name}
                        </span>
                        <p class="font-headline font-black text-on-surface text-base leading-tight">
                          {item.menu_item.name}
                        </p>
                      </div>
                      <div class="flex flex-wrap gap-x-3 gap-y-1 mt-1">
                        <%= for modifier <- modifiers do %>
                          <p class="text-[11px] font-black text-on-surface-variant uppercase tracking-tight opacity-60">
                            + {modifier.name}
                          </p>
                        <% end %>
                      </div>
                    </div>
                    <div class="flex items-center gap-3 shrink-0 pt-0.5">
                      <div class="flex flex-col items-end">
                        <span class="text-base font-black text-primary">
                          {basket_item_price(item, modifiers)}
                        </span>
                        <span class="text-[10px] font-black text-on-surface-variant opacity-60 uppercase">
                          Qty: {item.quantity}
                        </span>
                      </div>
                      
                      <div class="flex flex-col gap-2">
                        <button
                          phx-click="remove_cart_item"
                          phx-value-cart_item_id={item.id}
                          class="w-9 h-9 flex items-center justify-center rounded-lg bg-error/5 hover:bg-error hover:text-on-error transition-all active:scale-90 text-error/60"
                          aria-label="Remove item"
                        >
                          <span class="material-symbols-outlined !text-[18px]">delete</span>
                        </button>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <%= if not is_nil(@cart) and not Enum.empty?(@cart.cart_items) do %>
            <div class="bg-surface-container-low/50 backdrop-blur-md rounded-t-[2.5rem] px-6 pb-8 pt-6 shrink-0 space-y-6 shadow-[0px_-8px_32px_rgba(0,0,0,0.05)]">
              <div class="space-y-3">
                <div class="flex justify-between items-center text-sm font-black text-on-surface-variant uppercase tracking-widest opacity-60">
                  <span>Subtotal</span>
                  <span>{basket_subtotal_string(@cart)}</span>
                </div>
                <%= if basket_has_tax?(@tax_rate) do %>
                  <div class="flex justify-between items-center text-sm font-black text-on-surface-variant uppercase tracking-widest opacity-60">
                    <span>Tax ({basket_tax_percent_label(@tax_rate)}%)</span>
                    <span>{basket_tax_string(@cart, @tax_rate)}</span>
                  </div>
                <% end %>
                <div class="flex justify-between items-center pt-2 border-t border-on-surface/[0.05]">
                  <span class="font-headline text-xl font-black text-on-surface uppercase tracking-tight">Total</span>
                  <span class="font-headline text-3xl font-black text-primary leading-none">
                    {basket_total(@cart, @tax_rate)}
                  </span>
                </div>
              </div>

              <button
                phx-click="start_checkout"
                class="w-full bg-gradient-to-r from-primary to-primary-container text-on-primary font-black text-lg rounded-xl px-6 py-4 shadow-[0px_16px_32px_rgba(185,0,39,0.3)] hover:scale-[1.02] hover:shadow-[0px_20px_40px_rgba(185,0,39,0.4)] transition-all active:scale-95"
              >
                PROCEED TO CHECKOUT
              </button>
            </div>
          <% end %>
        <% else %>
          <.form
            for={%{}}
            phx-submit="place_order"
            class="overflow-y-auto flex-1 flex flex-col no-scrollbar"
          >
            <div class="flex-1 px-6 py-6 space-y-6">
              <div>
                <label class="font-headline block text-xs font-black uppercase tracking-[0.15em] text-on-surface-variant/70 mb-3 px-1">
                  Your Name <span class="text-primary">*</span>
                </label>
                <input
                  type="text"
                  name="customer_name"
                  required
                  placeholder="e.g. Alex Smith"
                  class="w-full px-5 py-3.5 rounded-xl bg-surface-container-low border-0 text-on-surface placeholder-on-surface-variant/30 text-base font-black focus:outline-none focus:ring-4 focus:ring-primary/10 transition-all shadow-inner"
                />
              </div>
              <div>
                <label class="font-headline block text-xs font-black uppercase tracking-[0.15em] text-on-surface-variant/70 mb-3 px-1">
                  Phone
                  <span class="text-on-surface-variant/40 normal-case font-medium lowercase italic">(optional)</span>
                </label>
                <input
                  type="tel"
                  name="customer_phone"
                  placeholder="e.g. 555-1234"
                  class="w-full px-5 py-3.5 rounded-xl bg-surface-container-low border-0 text-on-surface placeholder-on-surface-variant/30 text-base font-black focus:outline-none focus:ring-4 focus:ring-primary/10 transition-all shadow-inner"
                />
              </div>
              <div>
                <label class="font-headline block text-xs font-black uppercase tracking-[0.15em] text-on-surface-variant/70 mb-3 px-1">
                  Notes
                  <span class="text-on-surface-variant/40 normal-case font-medium lowercase italic">(optional)</span>
                </label>
                <textarea
                  name="notes"
                  rows="3"
                  placeholder="Allergies, special requests…"
                  class="w-full px-5 py-3.5 rounded-xl bg-surface-container-low border-0 text-on-surface placeholder-on-surface-variant/30 text-base font-black focus:outline-none focus:ring-4 focus:ring-primary/10 transition-all resize-none shadow-inner"
                />
              </div>
            </div>
            
            <div class="bg-surface-container-low/50 backdrop-blur-md rounded-t-[2.5rem] px-6 pb-8 pt-6 shrink-0 space-y-6 shadow-[0px_-8px_32px_rgba(0,0,0,0.05)]">
              <div class="space-y-3">
                <div class="flex justify-between items-center text-sm font-black text-on-surface-variant uppercase tracking-widest opacity-60">
                  <span>Subtotal</span>
                  <span>{basket_subtotal_string(@cart)}</span>
                </div>
                <%= if basket_has_tax?(@tax_rate) do %>
                  <div class="flex justify-between items-center text-sm font-black text-on-surface-variant uppercase tracking-widest opacity-60">
                    <span>Tax ({basket_tax_percent_label(@tax_rate)}%)</span>
                    <span>{basket_tax_string(@cart, @tax_rate)}</span>
                  </div>
                <% end %>
                <div class="flex justify-between items-center pt-2 border-t border-on-surface/[0.05]">
                  <span class="font-headline text-xl font-black text-on-surface uppercase tracking-tight">Total</span>
                  <span class="font-headline text-3xl font-black text-primary leading-none">
                    {basket_total(@cart, @tax_rate)}
                  </span>
                </div>
              </div>

              <button
                type="submit"
                class="w-full bg-gradient-to-r from-primary to-primary-container text-on-primary font-black text-lg rounded-xl px-6 py-4 shadow-[0px_16px_32px_rgba(185,0,39,0.3)] hover:scale-[1.02] hover:shadow-[0px_20px_40px_rgba(185,0,39,0.4)] transition-all active:scale-95"
              >
                PLACE ORDER
              </button>
            </div>
          </.form>
        <% end %>
      </div>
    </div>
    """
  end

  defp basket_find_modifiers(cart_item) do
    modifier_ids = MapSet.new(Enum.map(cart_item.selected_modifier_ids || [], &to_string/1))

    Enum.flat_map(cart_item.menu_item.modifier_groups || [], fn group ->
      Enum.filter(group.modifiers || [], &MapSet.member?(modifier_ids, to_string(&1.id)))
    end)
  end

  defp basket_item_price(cart_item, modifiers) do
    base =
      case cart_item.selected_size do
        %{price: size_price} -> size_price
        _ -> cart_item.menu_item.price
      end

    price =
      Enum.reduce(modifiers, base, fn modifier, acc ->
        if modifier.price_delta do
          case Money.add(acc, modifier.price_delta) do
            {:ok, total} -> total
            _ -> acc
          end
        else
          acc
        end
      end)

    Money.to_string!(price)
  rescue
    _ -> ""
  end

  def basket_subtotal_money(cart) do
    cart.cart_items
    |> Enum.reduce(nil, fn item, acc ->
      modifiers = basket_find_modifiers(item)

      base =
        case item.selected_size do
          %{price: size_price} -> size_price
          _ -> item.menu_item.price
        end

      item_price =
        Enum.reduce(modifiers, base, fn modifier, inner_acc ->
          if modifier.price_delta do
            case Money.add(inner_acc, modifier.price_delta) do
              {:ok, p} -> p
              _ -> inner_acc
            end
          else
            inner_acc
          end
        end)

      line_total = Money.mult!(item_price, item.quantity)

      if is_nil(acc) do
        line_total
      else
        case Money.add(acc, line_total) do
          {:ok, sum} -> sum
          _ -> acc
        end
      end
    end)
  end

  def basket_subtotal_string(cart) do
    case basket_subtotal_money(cart) do
      nil -> ""
      total -> Money.to_string!(total)
    end
  rescue
    _ -> ""
  end

  defp basket_has_tax?(tax_rate) do
    Decimal.compare(tax_rate, Decimal.new("0")) == :gt
  rescue
    _ -> false
  end

  defp basket_tax_percent_label(tax_rate) do
    tax_rate
    |> Decimal.mult(Decimal.new("100"))
    |> Decimal.normalize()
    |> Decimal.to_string()
  rescue
    _ -> "0"
  end

  defp basket_tax_string(cart, tax_rate) do
    case basket_subtotal_money(cart) do
      nil ->
        ""

      subtotal ->
        tax = Money.mult!(subtotal, tax_rate)
        Money.to_string!(tax)
    end
  rescue
    _ -> ""
  end

  defp basket_total(cart, tax_rate) do
    case basket_subtotal_money(cart) do
      nil ->
        ""

      subtotal ->
        tax = Money.mult!(subtotal, tax_rate)
        {:ok, total} = Money.add(subtotal, tax)
        Money.to_string!(total)
    end
  rescue
    _ -> ""
  end

  defp close_basket_js do
    JS.add_class("invisible pointer-events-none", to: "#basket-wrapper")
    |> JS.remove_class("visible", to: "#basket-wrapper")
    |> JS.remove_class("opacity-100", to: "#basket-backdrop")
    |> JS.add_class("opacity-0", to: "#basket-backdrop")
    |> JS.add_class("translate-y-full", to: "#basket-panel")
    |> JS.add_class("md:translate-x-full", to: "#basket-panel")
    |> JS.remove_class("translate-y-0", to: "#basket-panel")
    |> JS.remove_class("md:translate-x-0", to: "#basket-panel")
  end
end
