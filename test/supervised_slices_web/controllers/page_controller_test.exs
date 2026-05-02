defmodule SupervisedSlicesWeb.PageControllerTest do
  use SupervisedSlicesWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "More orders."
  end
end
