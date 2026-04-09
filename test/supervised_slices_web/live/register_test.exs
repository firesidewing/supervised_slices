defmodule SupervisedSlicesWeb.RegisterTest do
  use SupervisedSlicesWeb.ConnCase
  import Phoenix.LiveViewTest

  test "registration form renders organization_name field", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/register")
    # ash_authentication_phoenix version 2 uses the subject name as the form name.
    # For SupervisedSlices.Accounts.User, the subject name is :user.
    assert has_element?(view, "input[name='user[organization_name]']")
    assert render(view) =~ "Organization Name"
  end
end
