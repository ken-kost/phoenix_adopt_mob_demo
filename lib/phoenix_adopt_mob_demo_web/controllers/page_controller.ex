defmodule PhoenixAdoptMobDemoWeb.PageController do
  use PhoenixAdoptMobDemoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
