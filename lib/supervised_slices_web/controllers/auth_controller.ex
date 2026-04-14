defmodule SupervisedSlicesWeb.AuthController do
  use SupervisedSlicesWeb, :controller
  use AshAuthentication.Phoenix.Controller

  require Ash.Query

  def success(conn, {:password, :register}, user, _token) do
    org = get_admin_org(user)

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> put_flash(:info, "Welcome! Complete your subscription to activate your kitchen.")
    |> redirect(to: ~p"/billing/setup/#{org.slug}")
  end

  def success(conn, activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/"

    message =
      case activity do
        {:confirm_new_user, :confirm} -> "Your email address has now been confirmed"
        {:password, :reset} -> "Your password has successfully been reset"
        _ -> "You are now signed in"
      end

    kitchen_org = get_kitchen_org(user)

    redirect_to =
      if return_to == ~p"/" and kitchen_org do
        ~p"/kitchen/#{kitchen_org.slug}"
      else
        return_to
      end

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    # If your resource has a different name, update the assign name here (i.e :current_admin)
    |> assign(:current_user, user)
    |> put_flash(:info, message)
    |> redirect(to: redirect_to)
  end

  defp get_kitchen_org(user) do
    user.id
    |> SupervisedSlices.Orgs.Membership.get_kitchen_membership(authorize?: false)
    |> case do
      {:ok, [membership | _]} -> membership.organization
      _ -> nil
    end
  end

  defp get_admin_org(user) do
    SupervisedSlices.Orgs.Membership
    |> Ash.Query.filter(user_id == ^user.id and role == :admin)
    |> Ash.read_one!(authorize?: false, load: [:organization])
    |> Map.get(:organization)
  end

  def failure(conn, activity, reason) do
    message =
      case {activity, reason} do
        {_,
         %AshAuthentication.Errors.AuthenticationFailed{
           caused_by: %Ash.Error.Forbidden{
             errors: [%AshAuthentication.Errors.CannotConfirmUnconfirmedUser{}]
           }
         }} ->
          """
          You have already signed in another way, but have not confirmed your account.
          You can confirm your account using the link we sent to you, or by resetting your password.
          """

        _ ->
          "Incorrect email or password"
      end

    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> clear_session(:supervised_slices)
    |> put_flash(:info, "You are now signed out")
    |> redirect(to: return_to)
  end
end
