# PhoenixAdoptMobDemo

A worked, end-to-end example of dropping [Mob](https://github.com/ken-kost/mob)
into a **standard Postgres Phoenix LiveView app** with `mix mob.adopt` — from
`mix phx.new` to a running Android app, with on-device persistence (Postgres
on the server, SQLite on the phone) and a couple of native-bridge interactions.

It's also a field report: building it surfaced several real `mob.adopt` rough
edges, most now fixed upstream in [`mob_new`](https://github.com/ken-kost/mob_new).
The full step-by-step — rationale, diffs, and a troubleshooting table — lives
in **[demo-project-plan.md](demo-project-plan.md)**. This README is the map.

> **Before you copy this:** since it was built, `mob.adopt` tightened its
> guard ([`2f5f620`](https://github.com/ken-kost/mob_new/commit/2f5f620)) — in
> default LiveView mode it now **requires a SQLite host repo** and refuses
> Postgres. This demo adopts into Postgres and hand-wires a second SQLite repo
> for the device, which is basically a preview of the planned
> `--with-local-repo` mode. The *why* behind each step still holds; today's
> path just differs (start from SQLite, or pass `--no-live-view`).

## Two repos, one schema

A phone can't reach your server's Postgres, so the app keeps Postgres for the
server and a SQLite repo for the device:

| Where | Repo | Adapter |
|---|---|---|
| Server / dev / prod | `PhoenixAdoptMobDemo.Repo` | Postgres |
| On the device | `PhoenixAdoptMobDemo.LocalRepo` | SQLite |

Both compile into every build; only the **active** one starts. The supervision
tree starts whatever `:repo` points at (Postgres by default), and
[`mob_app.ex`](lib/phoenix_adopt_mob_demo/mob_app.ex) flips it to `LocalRepo`
and migrates SQLite before boot on-device. Same schema, same migrations, both
worlds — [full design](demo-project-plan.md#database-persistence-postgres-on-the-server-sqlite-on-device).

## The walkthrough — one commit per step

Each step was verified before the next, and the commit captures it.

| Step | What | Commit |
|---|---|---|
| 0 | `mix phx.new` base | [`ee714e0`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/ee714e0) |
| 1 | Phoenix LV + Ecto/Postgres base | [`1712713`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/1712713) |
| 2 | Add `:igniter` — mob.adopt's AST engine | [`ccd97e9`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/ccd97e9) |
| 3 | `mix mob.adopt` + wire the on-device SQLite repo | [`0bc33e0`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/0bc33e0) |
| 4 | `mix mob.install` first-run setup (OTP, NDK, icons) | [`a4318df`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/a4318df) |
| 5 | Verify local config | [`ce1b6dd`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/ce1b6dd) |
| 6 | Deploy to an Android emulator + 3 on-device fixes | [`ef9a62d`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/ef9a62d) |
| 7 | Verify the happy path on-device | [`4ec7ebb`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/4ec7ebb) |
| 8 | Native interaction #1 — vibrate, via the LiveView bridge | [`8d0396c`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/8d0396c) |
| 9 | Native interaction #2 — native toast | [`47e0811`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/47e0811) |
| 10 | Notes CRUD — persistence in both worlds | [`340d611`](https://github.com/ken-kost/phoenix_adopt_mob_demo/commit/340d611) |

**Verified on an x86_64 emulator (step 7):** the styled welcome page renders in
the WebView; LiveView connects on a live route (LiveDashboard runs on-device,
reporting `OTP 29 … x86_64-pc-linux-android`); the native bridge is live
(`window.mob` = `{send, onMessage, _dispatch}`); and `LocalRepo` migrates
SQLite at boot with no Postgres connection attempt.

**The UI demos (steps 8–10):** `/demo` has two buttons that round-trip a
`mob_message` to the LiveView and fire a native haptic / toast on-device;
`/notes` is a tiny CRUD whose notes persist to Postgres on the server and
SQLite on the phone — and survive a refresh.

## What it surfaced — and how `mob_new` responded

A happy-path demo earns its keep by finding the unhappy paths. Each row links
the demo's workaround and the upstream fix.

| # | Finding | Upstream |
|---|---|---|
| 1 | `mob.adopt` generated a `mob_app.ex` needing `:ecto_sqlite3` but never added the dep. | **Fixed** — LV mode now injects it. [`2f5f620`](https://github.com/ken-kost/mob_new/commit/2f5f620) |
| 2 | Adopt assumed the host repo was SQLite, so on-device it migrated **Postgres** — silently broken. | **Fixed by guarding** — refuses non-SQLite hosts in LV mode with guidance. [`2f5f620`](https://github.com/ken-kost/mob_new/commit/2f5f620) |
| 3 | `mob_app.ex` set `live_reload: false` → `FunctionClauseError` on every request. | **Fixed** — emits `live_reload: [patterns: []]`. [`907f4f6`](https://github.com/ken-kost/mob_new/commit/907f4f6) |
| 4 | The support matrix didn't mention the SQLite requirement or the `--no-live-view` escape hatch. | **Fixed** — `@moduledoc` restructured into Supported / Refused. [`2f5f620`](https://github.com/ken-kost/mob_new/commit/2f5f620) |
| 5 | **Port mismatch** — `mob_screen.ex` defaults to `:4000` but `mob_app.ex` binds a hashed port → `ERR_CONNECTION_REFUSED`. | **Open.** Workaround: `mob_app.ex` publishes the real `:host_url` before boot. |
| 6 | Deploy doesn't build frontend assets (→ `/assets/*` 404) and needs `zig` on PATH. | **Flow gaps.** Run `mix assets.build` and put `zig` on PATH before deploying. |
| 7 | Adopt doesn't gitignore `local.properties` or native build outputs. | **Open.** Added to this repo's `.gitignore`. |

## Run it locally

Needs Elixir 1.19+/OTP 28+, a local Postgres, the `mob_new` archive, the
Android SDK + a running AVD, and `zig` 0.16.x on PATH.

```bash
# Server
mix setup && mix phx.server          # http://localhost:4000 (try /demo and /notes)

# Device (Android)
export PATH="/path/to/zig:$PATH"     # if zig isn't already on PATH
mix assets.build                     # compile app.js/app.css for on-device
mix mob.deploy --native              # first run: build + install the APK
mix mob.deploy                       # after that: fast BEAM push + restart
```

Full steps and troubleshooting: [demo-project-plan.md](demo-project-plan.md).
