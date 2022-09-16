defmodule WordleIshWeb.PageController do
  use WordleIshWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
