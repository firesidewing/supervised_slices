defmodule SupervisedSlicesWeb.PageController do
  use SupervisedSlicesWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
