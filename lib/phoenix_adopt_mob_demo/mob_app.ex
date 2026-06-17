defmodule PhoenixAdoptMobDemo.MobApp do
  @moduledoc """
  BEAM entry point for the LiveView Mob app.

  Called from `src/phoenix_adopt_mob_demo.erl` by the iOS/Android native launcher.
  Starts the Phoenix OTP application (which boots the endpoint and all
  supervision trees), then opens the MobScreen WebView pointing at
  http://127.0.0.1:<liveview_port>/ (port set in mob.exs).

  This module is the LiveView equivalent of `Mob.App`. It does not use
  `use Mob.App` because Phoenix owns the supervision tree. Mob is added
  only as a WebView wrapper around the running Phoenix endpoint.
  """

  def start do
    Mob.NativeLogger.install()

    # On-device, Mix config files are not loaded — set Phoenix endpoint
    # config explicitly before starting applications so the endpoint knows
    # its port, adapter, and secret key base. Watchers and code reload
    # are omitted (no dev tools on-device).
    #
    # Port default is hashed from the app name into 4200..4999 so two
    # Mob LV apps installed on the same device don't fight over a
    # single hardcoded port (Bandit returns :eaddrinuse, the endpoint
    # supervisor crashes, BEAM dies). With 800 candidate ports and
    # `phash2`'s good distribution, collision odds are p<0.5% even
    # at five installed apps. Override in mob.exs by setting
    # `config :mob, liveview_port: <port>` if you need a specific value.
    liveview_port = Application.get_env(:mob, :liveview_port, default_liveview_port())
    Application.put_env(:mob, :liveview_port, liveview_port)

    # Point the WebView (MobScreen) at the on-device endpoint's ACTUAL
    # port. Without this the generated MobScreen falls back to its
    # hardcoded `http://127.0.0.1:4000/`, which doesn't match the hashed
    # `liveview_port` the endpoint binds — the WebView then shows
    # ERR_CONNECTION_REFUSED. Skip if a remote `host_url` was configured
    # (thin-client mode). (mob.adopt template mismatch — mob_new follow-up.)
    unless Application.get_env(:mob, :host_url) do
      Application.put_env(:mob, :host_url, "http://127.0.0.1:#{liveview_port}/")
    end

    Application.put_env(:phoenix_adopt_mob_demo, PhoenixAdoptMobDemoWeb.Endpoint,
      adapter: Bandit.PhoenixAdapter,
      http: [ip: {127, 0, 0, 1}, port: liveview_port],
      check_origin: false,
      debug_errors: true,
      server: true,
      secret_key_base: "tDByB+wjQ7rO495yASR/Teow+wWsp6+IdBFNnv/Aoo2h5ESIlEnhwQx16VhsQ93t",
      pubsub_server: PhoenixAdoptMobDemo.PubSub,
      live_view: [signing_salt: "OOKtnpS8Pps"],
      # Disable Phoenix LiveReload + code reloader on-device. The host
      # `mac_listener` binary isn't bundled (and couldn't watch a host
      # filesystem from inside an iOS sandbox anyway). Without these
      # flags the boot log gets a warning per missing tool.
      code_reloader: false,
      watchers: [],
      # The device build compiles with MIX_ENV=dev, so `code_reloading?`
      # is true and Phoenix.LiveReloader is in the pipeline. It reads
      # `config[:live_reload][:patterns]` — so this MUST be a keyword list,
      # not `false` (the generated value), which makes it crash with
      # `Access.get(false, :patterns, nil)` (FunctionClauseError) on every
      # request. Empty patterns = reloader present but inert.
      # (mob.adopt template bug — mob_new follow-up.)
      live_reload: [patterns: []]
    )

    # esbuild + tailwind are dev-time asset compilers. They get pulled in
    # as runtime apps but don't have access to their host config (which
    # lives in `config/dev.exs`, not bundled). Set their versions here so
    # the on-device boot log stays clean — they never actually run.
    # Versions match Phoenix 1.7's defaults; bump alongside `mix phx.new`.
    Application.put_env(:esbuild, :version, "0.25.0")
    Application.put_env(:tailwind, :version, "3.4.6")

    # On-device we persist to SQLite (LocalRepo), not the server's Postgres
    # (Repo). Select it BEFORE starting the app so the supervision tree
    # boots LocalRepo instead of Repo (see application.ex). This is the
    # piece `mob.adopt` can't infer for a Postgres host project — adopt's
    # default mob_app.ex assumes the host Repo is itself SQLite.
    Application.put_env(:phoenix_adopt_mob_demo, :repo, PhoenixAdoptMobDemo.LocalRepo)

    # ecto_sqlite3 must be started before phoenix_adopt_mob_demo so its NIF is
    # loaded before the LocalRepo supervisor tries to open the database.
    {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)

    # Start the Phoenix application and all its children.
    # This boots the endpoint, the active (SQLite) repo, pubsub, telemetry, etc.
    {:ok, _} = Application.ensure_all_started(:phoenix_adopt_mob_demo)

    # Run any pending migrations against the on-device SQLite repo. The same
    # migration files in priv/repo/migrations work on both Postgres and
    # SQLite for the demo's simple schema. MOB_BEAMS_DIR is set by the native
    # launcher to the flat deploy directory; migrations are copied there at
    # build time. Falls back to Application.app_dir when running in dev.
    Ecto.Migrator.with_repo(PhoenixAdoptMobDemo.LocalRepo, fn _repo ->
      Ecto.Migrator.run(PhoenixAdoptMobDemo.LocalRepo, migrations_dir(), :up, all: true)
    end)

    # ComponentRegistry is normally started by Mob.App but we bypass that.
    # Start it standalone so Mob.Screen.start_root can render components.
    {:ok, _} = Mob.ComponentRegistry.start_link()

    # Start the MobScreen WebView pointing at the local Phoenix endpoint.
    # The WebView loads http://127.0.0.1:<liveview_port>/ (see mob.exs).
    Mob.Screen.start_root(PhoenixAdoptMobDemo.MobScreen)

    # Start Erlang distribution so `mix mob.connect` can attach.
    Mob.Dist.ensure_started(
      node: :"phoenix_adopt_mob_demo_android@127.0.0.1",
      cookie: :mob_secret
    )
  end

  defp migrations_dir do
    case System.get_env("MOB_BEAMS_DIR") do
      nil -> Application.app_dir(:phoenix_adopt_mob_demo, "priv/repo/migrations")
      beams_dir -> Path.join([beams_dir, "priv", "repo", "migrations"])
    end
  end

  # 4200..4999 inclusive — small enough to leave room above the standard
  # dev range, large enough that birthday-paradox collisions are rare for
  # any reasonable number of installed Mob LV apps. Deterministic, so the
  # WebView URL stays stable across restarts.
  defp default_liveview_port do
    4200 + :erlang.phash2(:phoenix_adopt_mob_demo, 800)
  end
end
