defmodule PhoenixAdoptMobDemo.MobScreen do
  @moduledoc """
  Mob.Screen that wraps the host Phoenix app in a native WebView.

  Reads the URL from `config :mob, :host_url` (default
  `http://127.0.0.1:4000/`) so the same module works for the
  on-device BEAM (localhost) or a remote deployment (set
  `config :mob, host_url: "https://your-app.example.com/"`).
  """
  use Mob.Screen

  @default_host_url "http://127.0.0.1:4000/"

  def host_url do
    Application.get_env(:mob, :host_url, @default_host_url)
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(_assigns) do
    Mob.UI.webview(
      url: host_url(),
      show_url: false
    )
  end
end
