# PhoenixAdoptMobDemo

A worked, end-to-end example of adopting [Mob](https://github.com/ken-kost/mob)
into a **standard Ecto/Postgres Phoenix LiveView** app with `mix mob.adopt`,
all the way to a running app on an Android emulator — including the
**on-device persistence** story (Postgres on the server, SQLite on the
device).

It doubles as a field report: working through it surfaced several real
`mob.adopt` rough edges, most of which have since been fixed upstream in
[`mob_new`](https://github.com/ken-kost/mob_new) (see
[What this demo surfaced](#what-this-demo-surfaced--and-how-mob_new-responded)).

The full, step-by-step narrative — with rationale, expected diffs, and a
troubleshooting cheatsheet — lives in **[demo-project-plan.md](demo-project-plan.md)**.
This README is the map; the plan is the territory.

> **Heads-up on the blessed shape (read this first).** This demo adopts into
> a **Postgres** host and *manually* wires a second SQLite repo for the
> device. Since this was built, `mob.adopt`'s guard was tightened
> ([mob_new `2f5f620`](https://github.com/ken-kost/mob_new/commit/2f5f620)):
> in default **LiveView** mode it now **requires the host Repo to be SQLite**
> (`mix phx.new --database sqlite3`) and **refuses a Postgres host** with
> guidance. So today you'd either start from a SQLite host, pass
> `--no-live-view`, or wait for the planned `--with-local-repo` mode. What
> this demo builds by hand is essentially a preview of that `--with-local-repo`
> path. The walkthrough is still accurate for *why* each piece exists.

---

## The architecture: two repos, one schema

A phone can't reach your server's Postgres, and Mob bundles SQLite for
local persistence. So the project keeps a real Postgres repo for the
server and selects a SQLite repo on-device:

| Where | Repo | Adapter |
|---|---|---|
| Server / dev / prod | `PhoenixAdoptMobDemo.Repo` | `Ecto.Adapters.Postgres` |
| On the device (Mob) | `PhoenixAdoptMobDemo.LocalRepo` | `Ecto.Adapters.SQLite3` |

Both repos compile into every build; only the **active** one starts. The
supervision tree starts `Application.get_env(:phoenix_adopt_mob_demo, :repo, Repo)`
(Postgres by default), and [`mob_app.ex`](lib/phoenix_adopt_mob_demo/mob_app.ex)
flips `:repo` to `LocalRepo` before boot on-device and migrates SQLite.
See the [Database persistence](demo-project-plan.md#database-persistence-postgres-on-the-server-sqlite-on-device)
section of the plan for the full design.

---

## The walkthrough (one commit per step)

Each step was verified before moving on; the commit captures that step's
changes.

| Step | What | Commit |
|---|---|---|
| 0 | `mix phx.new` base | [`ee714e0`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/ee714e0) |
| 1 | Standard Phoenix LV + **Ecto/Postgres** base (Repo, config, migrations, aliases); verified compile + `ecto.create` + migrate | [`1712713`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/1712713) |
| 2 | Add `:igniter` — `mob.adopt` uses it for the AST work | [`ccd97e9`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/ccd97e9) |
| 3 | `mix mob.adopt` + **reconcile the on-device DB** (`LocalRepo`, target-aware supervision, `ecto_sqlite3`, `mob_app.ex` migrates SQLite) | [`0bc33e0`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/0bc33e0) |
| 4 | `mix mob.install` first-run setup (OTP runtimes, NDK, icons); gitignore machine-specific `local.properties` | [`a4318df`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/a4318df) |
| 5 | Verify local config (`mob.exs`, SDK paths) — `mob.install` already wrote it | [`ce1b6dd`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/ce1b6dd) |
| 6 | Deploy to an x86_64 emulator (`mix mob.deploy --native`) + **3 on-device fixes** | [`ef9a62d`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/ef9a62d) |
| 7 | **Verify the happy path** — all checks pass on-device | [`4ec7ebb`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/4ec7ebb) |

### Verified end-to-end (Step 7, on an x86_64 Android emulator)

- **Welcome page renders** — the styled Phoenix v1.8.8 page inside the WebView.
- **LiveView socket connects** — on a LiveView route (`/dev/dashboard/home`),
  `window.liveSocket.isConnected() === true`; the LiveDashboard renders live,
  reporting `Erlang/OTP 29 … [x86_64-pc-linux-android]`.
- **Native bridge is live** — `typeof window.mob === "object"`,
  `Object.keys(window.mob) === ["send","onMessage","_dispatch"]`.
- **On-device persistence** — `LocalRepo` (SQLite) migrates at boot
  (`Migrations already up`) and creates `app.db`, with no Postgres connection
  attempt. The two-repo wiring works on-device.

---

## What this demo surfaced — and how `mob_new` responded

The whole point of a happy-path demo is to find the unhappy paths. Each
finding below links the demo commit that worked around it and the
`mob_new` commit that fixed it upstream.

| # | Finding (demo) | Status upstream (`mob_new`) |
|---|---|---|
| 1 | `mob.adopt` generates a `mob_app.ex` that depends on `:ecto_sqlite3` but never adds the dep (only `mix mob.new` did). [`0bc33e0`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/0bc33e0) | **Fixed** — LV mode now injects `{:ecto_sqlite3, "~> 0.18"}` via a shared `inject_ecto_sqlite3/1` helper. [`2f5f620`](https://github.com/ken-kost/mob_new/commit/2f5f620) |
| 2 | Adopt emits a `mob_app.ex` that migrates a **Postgres** repo on-device (assumes the host Repo is SQLite) — silently broken. [`0bc33e0`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/0bc33e0) | **Fixed (by guarding)** — `AdoptGuard.check_repo_shape/1` now **refuses** a no-Ecto or non-SQLite (Postgres/MySQL/MSSQL) host in LV mode, naming the adapter and pointing at `--no-live-view` / switching to SQLite / the future `--with-local-repo`. [`2f5f620`](https://github.com/ken-kost/mob_new/commit/2f5f620) |
| 3 | `mob_app.ex` sets `live_reload: false`; `Phoenix.LiveReloader` does `config[:patterns]` → `FunctionClauseError` on **every request**. [`ef9a62d`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/ef9a62d) | **Fixed** — template now emits `live_reload: [patterns: []]` (reloader present but dormant). [`907f4f6`](https://github.com/ken-kost/mob_new/commit/907f4f6) |
| 4 | The experimental support matrix didn't spell out the Ecto/SQLite requirement or the `--no-live-view` escape hatch. | **Fixed** — `mix mob.adopt` `@moduledoc` restructured into Supported (LV) / Supported (`--no-live-view`) / Refused (loud, with guidance). [`2f5f620`](https://github.com/ken-kost/mob_new/commit/2f5f620) |
| — | Test coverage for the above | **Added** — acceptance test switched to `phx.new --database sqlite3` plus an `ensure_all_started(:ecto_sqlite3)` boot smoke-check (catches the dep-injection regression that `mix compile` misses), a `--no-live-view`-against-Postgres test, and 4 guard fixtures. [`de7266a`](https://github.com/ken-kost/mob_new/commit/de7266a) |
| 5 | **WebView port mismatch** — `mob_screen.ex` defaults the URL to `http://127.0.0.1:4000/`, but `mob_app.ex` binds the *hashed* `liveview_port` (e.g. 4743) → `ERR_CONNECTION_REFUSED`. [`ef9a62d`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/ef9a62d) | **Open upstream.** Worked around here by having `mob_app.ex` publish `:host_url` = `http://127.0.0.1:#{liveview_port}/` before boot. |
| 6 | Frontend assets aren't built by the deploy → `/assets/*` 404 (unstyled, no LiveView JS); and `zig` must be on PATH or the native build's CMake fallback fails. [`ef9a62d`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/ef9a62d) | **Flow gaps** (a `mob_dev`/deploy concern). Run `mix assets.build` and put `zig` on PATH before `mix mob.deploy --native`. |
| 7 | `mob.adopt` doesn't gitignore `android/local.properties` or native build outputs. [`a4318df`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/a4318df), [`ef9a62d`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/ef9a62d) | **Open upstream.** Added to this repo's `.gitignore`. |

---

## Reproduce it locally

Prerequisites: Elixir 1.19+/OTP 28+ (verified on 1.20.0/OTP 29), a reachable
Postgres (stock `postgres`/`postgres`), the `mob_new` archive
(`cd path/to/mob_new && mix archive.build && mix archive.install mob_new-<vsn>.ez`),
the Android SDK + a running AVD, and `zig` (0.16.x) on PATH.

```bash
# Server side
mix setup                      # deps + ecto.setup + assets
mix phx.server                 # http://localhost:4000

# Device side (Android)
which zig || export PATH="/path/to/zig:$PATH"
mix assets.build               # compile app.js / app.css for on-device
mix mob.deploy --native        # first deploy: build APK, install, push BEAMs
mix mob.deploy                 # fast: push changed BEAMs + restart
```

See [demo-project-plan.md](demo-project-plan.md) for the full step-by-step,
the post-step-7 Notes-CRUD persistence demo, and the troubleshooting table.

---

## Learn more about Phoenix

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
