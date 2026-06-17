defmodule PhoenixAdoptMobDemo.LocalRepo do
  @moduledoc """
  On-device Ecto repo, backed by SQLite.

  Postgres (`PhoenixAdoptMobDemo.Repo`) is the server-side database you
  develop and deploy against. A phone can't reach that Postgres, so the
  Mob build runs the same schema/migrations against a local SQLite file
  instead. `mob_app.ex` selects this repo on-device (see the
  `:repo` application env it sets before boot) and the application
  supervision tree starts whichever repo is active.

  The database file lives under `MOB_DATA_DIR` (the app's Documents
  directory, set by the native launcher); in host dev it falls back to a
  file in the project root so you can exercise the SQLite path locally.
  """
  use Ecto.Repo,
    otp_app: :phoenix_adopt_mob_demo,
    adapter: Ecto.Adapters.SQLite3

  @impl true
  def init(_type, config) do
    db_path =
      case System.get_env("MOB_DATA_DIR") do
        nil -> config[:database] || Path.join(File.cwd!(), "phoenix_adopt_mob_demo.db")
        dir -> Path.join(dir, "app.db")
      end

    {:ok, Keyword.merge(config, database: db_path, pool_size: 1)}
  end
end
