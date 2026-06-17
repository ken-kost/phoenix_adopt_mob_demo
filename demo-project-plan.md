# `mob.adopt` happy-path demo project — plan

Goal: prove `mix mob.adopt` works end-to-end against a fresh Phoenix
LiveView project, all the way to a running app on an Android emulator
(or iOS simulator), with a couple of native interactions wired
through `window.mob` so you can see the bridge is alive.

Audience: someone evaluating Mob who wants to confirm the
adopt-into-existing story before committing to a real project.

Total time: ~10 minutes hands-on. The slow bits are the first device
build (compiles BEAM + native shell) and the emulator startup.

---

## What the demo proves

1. **`mix mob.adopt` succeeds on a blessed-shape Phoenix LV project**
   — exit 0, no manual edits beyond `mob.exs` + `android/local.properties`.
2. **The bridge patches landed correctly** — `MobHook` in
   `assets/js/app.js`, bridge `<div>` in `root.html.heex`, all visible
   in `git diff`.
3. **The native app launches** — Phoenix LV page renders inside the
   WebView; channels reconnect; nothing webview-specific broken.
4. **JS↔native interop works** — at least one button on the LV page
   triggers a visible native side effect (toast / vibrate / camera).
5. **Persistence works in both worlds** — the same Ecto code persists to
   **Postgres** when run as a server and to **SQLite** on the device
   (see [Database persistence](#database-persistence-postgres-on-the-server-sqlite-on-device)).

The "few simple features" at the end are deliberately tiny — they
demonstrate the bridge is live, not the full Mob API surface.

---

## Prerequisites

| | |
|---|---|
| Elixir + OTP | 1.19+ / OTP 28+ — match `mob_new`'s `.tool-versions` (this demo verified on Elixir 1.20.0 / OTP 29) |
| `mob_new` | Installed as a Mix archive. From Hex: `mix archive.install hex mob_new`. From a local clone (pre-1.0, recommended): `cd path/to/mob_new && mix archive.build && mix archive.install mob_new-<vsn>.ez` |
| `:igniter` | The target project must declare `{:igniter, "~> 0.7", only: [:dev, :test]}` |
| Android | Android Studio + an AVD running, OR a physical device with USB debugging |
| iOS (optional) | Xcode 15+ + simulator OR a physical iPhone enrolled with your Apple ID |
| `mob` / `mob_dev` | Local clones (for `--local`) OR pinned Hex versions (whatever the latest is) |

If you don't have local `mob` / `mob_dev` clones, skip the `--local`
flag in step 3 and rely on Hex.

---

## Step 1 — Generate the Phoenix LiveView project

```bash
mix phx.new phoenix_adopt_mob_demo --no-mailer
cd phoenix_adopt_mob_demo
```

> This demo uses the project name `phoenix_adopt_mob_demo`; substitute your
> own app name throughout (the generated paths follow `lib/<app>/...`).

What we ask Phoenix to skip — and what we deliberately keep:
- `--no-mailer` — don't bring up Swoosh; nothing in the demo uses email.
- **We keep Ecto/Postgres** (the `mix phx.new` default — no `--no-ecto`).
  A real database is the standard Phoenix shape, and it lets the demo
  show genuine persistence. The on-device story still uses Mob's
  bundled SQLite — see [Database persistence](#database-persistence-postgres-on-the-server-sqlite-on-device)
  for how the two relate (Postgres on the server you develop/deploy
  against, SQLite on the device).

LiveView and the asset pipeline come along by default. That's
intentional — `mob.adopt`'s blessed shape requires `:phoenix_live_view`
and the stock `assets/js/app.js`.

You need a Postgres reachable with the stock dev credentials
(`postgres`/`postgres` on `localhost`), or edit `config/dev.exs` to
match yours. Then create the DB, run migrations, and confirm a clean
compile before we touch anything:

```bash
mix deps.get
mix ecto.create
mix ecto.migrate          # no app migrations yet — just creates schema_migrations
mix compile
```

---

## Step 2 — Add Igniter to the project's deps

`mob.adopt` runs against the host's `igniter` (the mob_new archive
loads its task code from the archive, but uses the target project's
`:igniter` for all the AST work). Edit `mix.exs`:

```elixir
defp deps do
  [
    {:phoenix, "~> 1.8"},
    # ... existing deps ...
    {:igniter, "~> 0.7", only: [:dev, :test]}  # ← add this
  ]
end
```

Fetch:

```bash
mix deps.get
```

---

## Step 3 — Adopt Mob

```bash
mix mob.adopt
```

That's it. Default (LV bridge) mode. The task will:

1. Add `:mob` + `:mob_dev` to `mix.exs`
2. Inject `MobHook` into `assets/js/app.js`
3. Inject the bridge `<div>` into
   `lib/phoenix_adopt_mob_demo_web/components/layouts/root.html.heex`
4. Generate `lib/phoenix_adopt_mob_demo/mob_screen.ex`
5. Generate `lib/phoenix_adopt_mob_demo/mob_app.ex` + `src/phoenix_adopt_mob_demo.erl`
6. Patch `erlc_paths`/`erlc_options` in `mix.exs`
7. Write `mob.exs` + append to `.gitignore`
8. Emit the `android/` and `ios/` native trees

Inspect what changed:

```bash
git status                       # lots of new files; mix.exs edited
git diff mix.exs                 # see the dep additions and erlc_*
git diff assets/js/app.js        # MobHook + LiveSocket registration
git diff lib/phoenix_adopt_mob_demo_web/components/layouts/root.html.heex
```

If your run fails with "requires a Phoenix project" or "requires
`new LiveSocket(`", you've drifted from the blessed shape — see
`mix help mob.adopt` for the supported list.

Fetch the new deps:

```bash
mix deps.get
mix compile
```

The compile must succeed before continuing. If it doesn't, the
generated `mob_app.ex` / `mob_screen.ex` referenced something the
host doesn't have — file an issue.

### On-device database — reconciling a Postgres host (Step 3 wiring)

`mob.adopt`'s generated `mob_app.ex` assumes the host's `Repo` is
*itself* SQLite (the `mix mob.new` shape): it starts `:ecto_sqlite3`
and runs `Ecto.Migrator` against `<App>.Repo` directly. A standard
Phoenix app uses **Postgres**, which can't run on a phone. So this demo
keeps Postgres on the server and adds a second SQLite repo for the
device. Step 3's commit wires this up — see
[Database persistence](#database-persistence-postgres-on-the-server-sqlite-on-device)
for the full design. In short:

1. Add the SQLite adapter dep — `{:ecto_sqlite3, "~> 0.18"}`.
2. Add `lib/<app>/local_repo.ex` (`Ecto.Adapters.SQLite3`, DB file under
   `MOB_DATA_DIR`).
3. Make the supervision tree start the **active** repo:
   `Application.get_env(:<app>, :repo, <App>.Repo)` (Postgres default).
4. In `mob_app.ex`, before boot, select SQLite for the device —
   `Application.put_env(:<app>, :repo, <App>.LocalRepo)` — and migrate
   `LocalRepo` (not the Postgres `Repo`).

> **Two `mob.adopt` gaps this surfaces** (both tracked as `mob_new`
> follow-ups): adopt does **not** add `:ecto_sqlite3` even though the
> `mob_app.ex` it generates hard-depends on it (only `mix mob.new` adds
> it, via `inject_ecto_sqlite3_dep`); and adopt does not detect a
> non-SQLite host `Repo`, so it emits a `mob_app.ex` that would start
> `ecto_sqlite3` yet migrate a Postgres repo on-device. Until those are
> fixed, the four steps above are manual.

---

## Step 4 — Run mob_dev's first-run setup

Different task — same name, different owner. `mob.install` is shipped
by `:mob_dev` (which `mob.adopt` just added to your deps). Runs once
per device. It:

1. **Writes the local config for you** — detects sensible defaults and
   writes `mob.exs` (`mob_dir`, `elixir_lib`) and
   `android/local.properties` (`sdk.dir`, OTP cache paths). This is most
   of Step 5 — for the Hex-based flow you usually don't edit anything.
2. **Downloads + caches the OTP runtime tarballs** (Android arm64/arm32/
   x86_64; iOS too on macOS). On a non-macOS host the **iOS OTP is
   skipped** — so Android is the only deploy target on Linux.
3. **Installs the Android NDK** if missing, and writes placeholder app
   icons (replace later with `mix mob.icon`).

```bash
mix mob.install
```

Follow the prompts (the defaults are fine for a demo). Verified output
on this Linux host: Android OTP cached under `~/.mob/cache`, NDK
installed, iOS OTP skipped, placeholder icons written.

---

## Step 5 — Local configuration (verify what Step 4 wrote)

`mix mob.install` already populated these in Step 4. This step is just
to **review** them — and to **edit** only if you're using a local `mob`
checkout or your SDK lives somewhere non-standard.

### `mob.exs` (gitignored, machine-specific)

For the **Hex** flow, `mob.install` writes `mob_dir: "deps/mob"` and
auto-derives `elixir_lib` from your running Elixir — no edit needed:

```elixir
# mob.exs (as written by mob.install — Hex flow)
import Config
config :mob_dev,
  mob_dir: Path.join(File.cwd!(), "deps/mob"),
  elixir_lib:
    System.get_env("MOB_ELIXIR_LIB", :code.lib_dir(:elixir) |> to_string() |> Path.dirname())
```

If you're a **Mob contributor using a local clone** (`mix mob.adopt
--local`), point `mob_dir` at it instead, e.g.
`mob_dir: "/home/you/code/mob"`.

### Android SDK — `android/local.properties` (gitignored)

`mob.install` writes `sdk.dir` plus the OTP cache paths. Confirm
`sdk.dir` points at a real SDK:

```ini
# android/local.properties (machine-specific; gitignored)
sdk.dir=/home/you/Android/Sdk             # Linux
# sdk.dir=/Users/you/Library/Android/sdk  # macOS
mob.otp_release=/home/you/.mob/cache/otp-android-<tag>
# …arm32 / x86_64 paths…
```

> **Note — `local.properties` should be gitignored.** Like `mob.exs`, it
> holds machine-specific paths and the file header says "NOT committed
> to version control" — but `mob.adopt` tracks it (only `mob.exs` gets
> the `.gitignore` entry). This demo adds `android/local.properties` to
> `.gitignore` and untracks it. Tracked as a `mob_new` follow-up: adopt
> should ignore `local.properties` too.

---

## Step 6 — Deploy to device

Start your Android emulator first (or plug in a physical device with
USB debugging enabled). Two prerequisites the bare `mob.deploy` doesn't
handle for you:

```bash
# 1. zig must be on PATH — the native build cross-compiles the BEAM +
#    NIFs with `zig build`. Without it, the build silently skips the
#    zig step and the CMake fallback fails ("Cannot find source file").
which zig || export PATH="/path/to/zig:$PATH"   # 0.16.x works here

# 2. Build the frontend assets — there's no esbuild/tailwind watcher
#    on-device, so app.js / app.css must be pre-compiled into
#    priv/static/assets or they 404 (unstyled page, no LiveView JS).
mix assets.build

# 3. Deploy (first run builds the APK; later runs are fast).
mix mob.deploy --native
```

First build is slow (~1–5 min) — it's compiling the native shell,
packaging the BEAM, building the APK, and signing. Subsequent
deploys (without `--native`) skip the native rebuild and just push
the changed BEAMs (~2–3 sec).

When the build finishes, the app launches on the device. You should
see the Phoenix LiveView welcome page rendered inside the WebView.

### On-device fixes — three `mob.adopt` template bugs

Getting a clean first launch surfaced three issues in the generated
`mob_app.ex` (all verified on an x86_64 Android emulator; all tracked
as `mob_new` follow-ups). This demo fixes them in `mob_app.ex`:

1. **WebView port mismatch → `ERR_CONNECTION_REFUSED`.** `mob_screen.ex`
   defaults the WebView URL to `http://127.0.0.1:4000/`, but `mob_app.ex`
   boots the endpoint on a *hashed* `liveview_port` (e.g. 4743). Fix:
   `mob_app.ex` publishes the real URL before boot —
   `Application.put_env(:mob, :host_url, "http://127.0.0.1:#{liveview_port}/")`
   (unless a remote `host_url` is configured).
2. **`live_reload: false` → `FunctionClauseError` on every request.** The
   device build compiles with `MIX_ENV=dev`, so `Phoenix.LiveReloader` is
   in the pipeline; it does `config[:live_reload][:patterns]`, which
   crashes when the value is the boolean `false`. Fix: set
   `live_reload: [patterns: []]` (reloader present but inert).
3. **Assets 404 (covered above).** Strictly a flow gap, not `mob_app.ex`:
   `mix mob.deploy --native` should run `mix assets.build` (or
   `assets.deploy`) so compiled CSS/JS are bundled. Until then, build
   them yourself first.

Also note: `mob.adopt` doesn't gitignore the native build outputs
(`android/.gradle`, `android/app/build`, `.cxx`, `.zig-cache`,
`jniLibs`, generated `java/io/`, `priv/generated`). This demo adds them
to `.gitignore`.

### iOS variant

```bash
MOB_TARGET=ios mix mob.deploy --native
```

For the simulator, no provisioning needed. For a physical iPhone,
run `mix mob.provision` once first to register the bundle ID and
download a development profile.

---

## Step 7 — Verify the happy path

Without writing any extra code, confirm these all work in the
deployed app. **All five were verified on an x86_64 Android emulator
for this demo** (results noted):

- [x] **Welcome page renders** (Phoenix's standard `PageController.home`)
      — the styled Phoenix v1.8.8 welcome page renders in the WebView.
- [x] **LiveView socket connects** — the welcome page is a *controller*
      page (no LV), so its `liveSocket.isConnected()` is `false` and
      that's correct. Navigating to a LiveView route (e.g.
      `/dev/dashboard/home`) gives `isConnected() === true` and the
      LiveDashboard renders live on-device.
- [x] **Refresh / navigation works** — navigating `/` → `/dev/dashboard`
      reconnects cleanly.
- [x] **`window.mob` is the native bridge** — in the WebView devtools
      (Safari Web Inspector for iOS; `chrome://inspect` or the CDP
      endpoint for Android):
      ```javascript
      typeof window.mob          // → "object"
      Object.keys(window.mob)    // → ["send","onMessage","_dispatch"]
      ```
      If it's `"undefined"`, the native shell didn't inject — re-run
      `mix mob.deploy --native` and check Logcat / the device console.
- [x] **On-device persistence** — the on-device SQLite `LocalRepo`
      migrates at boot (`[info] Migrations already up`) and creates
      `app.db` in the app's data dir, with no Postgres connection
      attempt. Confirms the two-repo wiring (Step 3) works on-device.

> Tip for headless verification: `adb forward tcp:9222
> localabstract:webview_devtools_remote_<pid>`, then drive the WebView
> over the Chrome DevTools Protocol (`http://localhost:9222/json`) to
> evaluate `typeof window.mob` and `liveSocket.isConnected()`.

At this point you've proven `mob.adopt` works end-to-end on the
blessed shape. Steps 8–10 below are the "wow factor" — feel free to
stop here if you just wanted to confirm the install path.

---

## Step 8 — Native interaction #1: vibrate on tap

Tiny but visceral: a button that buzzes the phone through the bridge.
Two things to get right — both surfaced while verifying in the browser,
and both differ from this plan's first draft:

- **Put it on a LiveView, not the welcome page.** The stock welcome page
  (`PageController.home`) is a *controller* (dead) page — a `phx-hook`
  never mounts there, so the LiveView bridge can't fire. Add a dedicated
  `DemoLive` at `/demo` and link to it from home (the same "separate
  LiveView route" pattern Step 10 uses for `/notes`). This keeps Step
  7's verified stock welcome page intact.
- **Trigger via an in-view hook's `pushEvent`, not `window.mob.vibrate`.**
  There is no `window.mob.vibrate` — the JS bridge API is
  `send`/`onMessage`/`_dispatch`, and native effects are Elixir-side
  (`Mob.Haptic`). In LiveView-bridge mode `window.mob.send` is literally
  `(data) => this.pushEvent("mob_message", data)`, so we push that same
  `"mob_message"` event from a hook *inside* `DemoLive` (see the bridge
  note at the end of the step for why "inside" matters).

Create `lib/phoenix_adopt_mob_demo_web/live/demo_live.ex`:

```elixir
defmodule PhoenixAdoptMobDemoWeb.DemoLive do
  use PhoenixAdoptMobDemoWeb, :live_view

  def mount(_params, _session, socket),
    do: {:ok, assign(socket, events: [], page_title: "Native bridge demo")}

  def handle_event("mob_message", %{"action" => "vibrate"}, socket) do
    if native?(), do: Mob.Haptic.trigger(socket, :medium)
    {:noreply, log(socket, "📳 vibrate → Mob.Haptic.trigger(:medium)")}
  end

  # Catch-all so an unhandled bridge message can never crash the LiveView.
  def handle_event("mob_message", _payload, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>Native bridge demo</.header>
      <div class="mt-8 flex flex-wrap gap-3">
        <button id="vibrate-btn" phx-hook="VibrateBtn"
          class="rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white">
          Buzz the phone
        </button>
      </div>
      <ul id="event-log" class="mt-8 ...">
        <li :for={{event, i} <- Enum.with_index(@events)} id={"event-#{i}"}>{event}</li>
      </ul>
    </Layouts.app>
    """
  end

  defp log(socket, msg), do: update(socket, :events, &Enum.take([msg | &1], 8))

  # True only on a device — the NIF raises when not loaded (mirrors
  # Mob.App.safe_platform/0). Guards every native call so the page also
  # runs in a plain browser.
  defp native? do
    :mob_nif.platform() in [:ios, :android]
  rescue
    _ -> false
  end
end
```

In `assets/js/app.js`, after the existing `MobHook`, add the hook and
register it in the `LiveSocket` initialiser:

```javascript
const VibrateBtn = {
  mounted() {
    this.el.addEventListener("click", () => {
      this.pushEvent("mob_message", {action: "vibrate"})
    })
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: {MobHook, VibrateBtn, ...colocatedHooks},   // ← add VibrateBtn
  params: {_csrf_token: csrfToken},
})
```

Add the route and a link from home:

```elixir
# router.ex — inside scope "/" with pipe_through :browser
live "/demo", DemoLive
```

```heex
<%!-- home.html.heex --%>
<.link navigate={~p"/demo"} class="...">Native bridge demo &rarr;</.link>
```

Redeploy (Phoenix-only change — no native rebuild needed):

```bash
mix mob.deploy
```

On the device, tap **Buzz the phone** → the phone buzzes (`native?/0`
lets `Mob.Haptic.trigger/2` run). In a plain browser the NIF is absent,
the guard skips it, and the round-trip is appended to the on-page log —
which is how you verify the JS → LiveView path without a device.

> **Bridge note — why an *in-view* hook.** `mix mob.adopt` injects
> `MobHook` on `<div id="mob-bridge">` in `root.html.heex`. In Phoenix
> 1.8's layout model that element is a sibling of `{@inner_content}` —
> **outside** the LiveView container — so the `window.mob` it installs
> has a `pushEvent` that never reaches the page LiveView (verified: no
> `HANDLE EVENT` is logged when you call it). A hook on an element
> *inside* `DemoLive` (like `VibrateBtn`) pushes to `DemoLive` correctly,
> using the identical `"mob_message"` contract. Tracked as a `mob_new`
> follow-up: emit the bridge element inside the app layout so
> `window.mob` works directly on LiveView pages.

---

## Step 9 — Native interaction #2: native toast

Even simpler — call a native dialog so the platform's own UI renders on
top of the WebView. Same mechanism as Step 8: a second button on
`/demo`, a hook that pushes `"mob_message"`, and a `handle_event/3`
clause that calls `Mob.Alert.toast/2` on-device.

Add the button to `DemoLive`'s render, next to the vibrate one:

```heex
<button id="toast-btn" phx-hook="ToastBtn"
  class="rounded-lg bg-emerald-700 px-4 py-2 text-sm font-semibold text-white">
  Show a native toast
</button>
```

Add the `handle_event/3` clause (before the catch-all):

```elixir
def handle_event("mob_message", %{"action" => "toast", "message" => message}, socket) do
  if native?(), do: Mob.Alert.toast(socket, message)
  {:noreply, log(socket, "🔔 toast → Mob.Alert.toast(#{inspect(message)})")}
end
```

Add the hook in `app.js` and register it alongside the others
(`hooks: {MobHook, VibrateBtn, ToastBtn, ...colocatedHooks}`):

```javascript
const ToastBtn = {
  mounted() {
    this.el.addEventListener("click", () => {
      this.pushEvent("mob_message", {action: "toast", message: "Hello from native!"})
    })
  }
}
```

Redeploy with `mix mob.deploy`, tap the button. A native toast (Android)
or floating overlay (iOS) appears. In the browser the round-trip logs to
the same on-page list, passing the message payload through.

---

## Database persistence: Postgres on the server, SQLite on-device

The demo project keeps the stock `mix phx.new` database setup — a real
**Postgres** repo (`PhoenixAdoptMobDemo.Repo`) — because that's the
standard Phoenix shape and what you develop and deploy against. Mob's
on-device story, however, is **SQLite**: a phone can't reach your
server's Postgres, and Mob bundles SQLite (`ecto_sqlite3` / `exqlite`)
for local, offline-first persistence.

These are two databases, selected by where the BEAM is running:

| Where | Repo | Adapter | When |
|---|---|---|---|
| Server / `mix phx.server` / dev / prod | `PhoenixAdoptMobDemo.Repo` | `Ecto.Adapters.Postgres` | host build |
| On the device (Mob) | `PhoenixAdoptMobDemo.LocalRepo` | `Ecto.Adapters.SQLite3` | native build |

### How the active repo is chosen

Both repos compile into every build; only one is *started*. The
supervision tree starts whichever repo `:repo` app-env points at,
defaulting to Postgres:

```elixir
# lib/phoenix_adopt_mob_demo/application.ex
children = [
  PhoenixAdoptMobDemoWeb.Telemetry,
  Application.get_env(:phoenix_adopt_mob_demo, :repo, PhoenixAdoptMobDemo.Repo),
  # …
]
```

`mob_app.ex` (the on-device BEAM entry point) flips that to SQLite
*before* the app starts, then migrates the SQLite repo:

```elixir
# lib/phoenix_adopt_mob_demo/mob_app.ex  (inside start/0)
Application.put_env(:phoenix_adopt_mob_demo, :repo, PhoenixAdoptMobDemo.LocalRepo)
{:ok, _} = Application.ensure_all_started(:ecto_sqlite3)
{:ok, _} = Application.ensure_all_started(:phoenix_adopt_mob_demo)

Ecto.Migrator.with_repo(PhoenixAdoptMobDemo.LocalRepo, fn _repo ->
  Ecto.Migrator.run(PhoenixAdoptMobDemo.LocalRepo, migrations_dir(), :up, all: true)
end)
```

The SQLite repo stores its file under `MOB_DATA_DIR` (the app's
Documents directory on-device), falling back to a file in the project
root for host dev so you can exercise the SQLite path locally:

```elixir
# lib/phoenix_adopt_mob_demo/local_repo.ex
defmodule PhoenixAdoptMobDemo.LocalRepo do
  use Ecto.Repo, otp_app: :phoenix_adopt_mob_demo, adapter: Ecto.Adapters.SQLite3

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
```

The same migration files in `priv/repo/migrations` run on both adapters
(for simple schemas). `config :phoenix_adopt_mob_demo, ecto_repos:
[…Repo]` still lists only Postgres, so host `mix ecto.*` tasks target
Postgres; the device migrates SQLite via `mob_app.ex` at boot.

> This two-repo reconciliation is the part `mob.adopt` does **not** do
> for a Postgres host (see the note under Step 3). It's a small,
> one-time wiring — and a candidate for `mob.adopt` to automate.

Any code that reads/writes data should go through the active repo so it
works in both worlds — e.g. a context helper:

```elixir
defp repo, do: Application.get_env(:phoenix_adopt_mob_demo, :repo, PhoenixAdoptMobDemo.Repo)
```

The next step puts this to work with a tiny persisted feature.

---

## Step 10 — Persistence demo: a tiny Notes CRUD

A minimal LiveView that writes to and reads from the database — proving
persistence end-to-end: Postgres when you run it as a normal Phoenix
server, SQLite when it runs on the device. Survives refresh / reconnect
because it's in a database, not socket state.

**Schema + migration.** Generate or hand-write:

```bash
mix ecto.gen.migration create_notes
```

```elixir
# priv/repo/migrations/<timestamp>_create_notes.exs
defmodule PhoenixAdoptMobDemo.Repo.Migrations.CreateNotes do
  use Ecto.Migration

  def change do
    create table(:notes) do
      add :body, :string, null: false
      timestamps(type: :utc_datetime)
    end
  end
end
```

```elixir
# lib/phoenix_adopt_mob_demo/notes/note.ex
defmodule PhoenixAdoptMobDemo.Notes.Note do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notes" do
    field :body, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:body])
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: 280)
  end
end
```

**Context — note it goes through the active repo**, so the same code
persists to Postgres on the server and SQLite on the device:

```elixir
# lib/phoenix_adopt_mob_demo/notes.ex
defmodule PhoenixAdoptMobDemo.Notes do
  import Ecto.Query, warn: false
  alias PhoenixAdoptMobDemo.Notes.Note

  defp repo, do: Application.get_env(:phoenix_adopt_mob_demo, :repo, PhoenixAdoptMobDemo.Repo)

  def list_notes, do: repo().all(from n in Note, order_by: [desc: n.inserted_at])
  def change_note(note \\ %Note{}, attrs \\ %{}), do: Note.changeset(note, attrs)

  def create_note(attrs) do
    %Note{} |> Note.changeset(attrs) |> repo().insert()
  end
end
```

**LiveView + route.** Add `live "/notes", NotesLive` to the router's
browser scope, and:

```elixir
# lib/phoenix_adopt_mob_demo_web/live/notes_live.ex
defmodule PhoenixAdoptMobDemoWeb.NotesLive do
  use PhoenixAdoptMobDemoWeb, :live_view
  alias PhoenixAdoptMobDemo.Notes

  def mount(_p, _s, socket), do: {:ok, socket |> assign_form() |> load()}

  def handle_event("save", %{"note" => params}, socket) do
    case Notes.create_note(params) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Saved.") |> assign_form() |> load()}
      {:error, cs} -> {:noreply, assign(socket, form: to_form(cs))}
    end
  end

  defp assign_form(socket), do: assign(socket, form: to_form(Notes.change_note()))
  defp load(socket), do: assign(socket, notes: Notes.list_notes())

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>Notes<:subtitle>Postgres on the server, SQLite on-device.</:subtitle></.header>
      <.form for={@form} id="note-form" phx-submit="save" class="mt-6 flex gap-2">
        <div class="flex-1"><.input field={@form[:body]} type="text" placeholder="Write a note…" /></div>
        <.button>Save</.button>
      </.form>
      <ul id="notes" class="mt-8 divide-y divide-zinc-200">
        <li :for={n <- @notes} id={"note-#{n.id}"} class="py-3">{n.body}</li>
        <li :if={@notes == []} class="py-3 text-zinc-500">No notes yet — add one; it survives a refresh.</li>
      </ul>
    </Layouts.app>
    """
  end
end
```

Link to it from home, next to the Step 8 `/demo` link
(`page_html/home.html.heex`):

```heex
<.link navigate={~p"/notes"} class="...">
  Notes demo (DB persistence) &rarr;
</.link>
```

**Run it both ways:**

- Server: `mix ecto.migrate && mix phx.server`, open `/notes`, add a
  note, refresh — it persists to Postgres.
- Device: `mix mob.deploy` (Phoenix-only change), open the app, navigate
  to `/notes`, add a note, kill and relaunch the app — it persists to
  the on-device SQLite file. No server, no network.

---

## Cleanup / iteration

Day-to-day after the demo:

```bash
mix mob.deploy        # fast: push changed BEAMs, restart on device
mix mob.watch         # auto-deploy on file save
mix mob.connect       # IEx attached to the device's BEAM
```

The `--native` flag is only needed when you change Elixir startup
sequence, native code under `android/`/`ios/`, or `mob.exs`. Phoenix
LV / HEEx / JS changes only need `mix mob.deploy`.

---

## Expected diff after Step 3 (sanity check)

Things `mob.adopt` should have added:

```
?? android/
?? ios/
?? lib/phoenix_adopt_mob_demo/mob_app.ex
?? lib/phoenix_adopt_mob_demo/mob_screen.ex
?? src/                                                        # phoenix_adopt_mob_demo.erl
 M .gitignore                                                  # +mob.exs
 M assets/js/app.js                                            # MobHook
 M lib/phoenix_adopt_mob_demo_web/components/layouts/root.html.heex   # bridge div
 M mix.exs                                                     # +:mob, +:mob_dev, +erlc_*
```

Note `mob.exs` is generated **and** added to `.gitignore` in the same
run, so plain `git status` shows it as *ignored* (`!!` under
`git status --ignored`), not untracked (`??`). That's expected — it
holds machine-local paths.

If you see anything OUTSIDE that list modified, file an issue —
adopt should be purely additive to the blessed shape.

On top of adopt's output, this demo **manually** adds the on-device
SQLite wiring (see [On-device database](#on-device-database--reconciling-a-postgres-host-step-3-wiring)),
which `git diff` will also show:

```
?? lib/phoenix_adopt_mob_demo/local_repo.ex                     # SQLite repo
 M lib/phoenix_adopt_mob_demo/application.ex                    # active-repo selection
 M lib/phoenix_adopt_mob_demo/mob_app.ex                        # select + migrate SQLite on-device
 M mix.exs                                                      # +:ecto_sqlite3
```

---

## Troubleshooting cheatsheet

| Symptom | Cause / fix |
|---|---|
| `task "mob.adopt" could not be found` | `mob_new` archive isn't installed. `mix archive.install hex mob_new`. |
| `mob.adopt requires a Phoenix project` | The target's `mix.exs` doesn't have `:phoenix` in deps. Confirm `mix phx.new` ran successfully. |
| `requires a stock new LiveSocket(...)` | The project's `assets/js/app.js` isn't shaped like `mix phx.new`'s output. Either restore the stock file or use `mix mob.adopt --no-live-view` (thin-client mode). |
| `requires a <body> tag in root.html.heex` | Same idea — heavily customised root layout. Restore the stock layout or use `--no-live-view`. |
| `mix compile` fails after adopt | The generated `mob_app.ex` referenced a Mob module that isn't in your `:mob` version. Check Mob's CHANGELOG for breaking changes since `mob_new`'s template. |
| `(UndefinedFunctionError) ... Ecto.Migrator` / `ecto_sqlite3` not started | The generated `mob_app.ex` needs `:ecto_sqlite3`, which `mob.adopt` doesn't add. Add `{:ecto_sqlite3, "~> 0.18"}` to deps. See [On-device database](#on-device-database--reconciling-a-postgres-host-step-3-wiring). |
| On-device boot crashes trying to reach Postgres | The active repo wasn't switched to SQLite. Confirm `mob_app.ex` sets `:repo` to `<App>.LocalRepo` *before* `ensure_all_started`, and that `application.ex` starts the active repo (not a hardcoded Postgres `Repo`). |
| Native build fails: `CMake ... Cannot find source file` | `zig` isn't on PATH, so the `zig build` step was skipped and the CMake fallback can't find the generated sources. Put zig (0.16.x) on PATH and re-run. |
| WebView: `ERR_CONNECTION_REFUSED` at `http://127.0.0.1:4000/` | Port mismatch — `mob_screen.ex` defaults to 4000 but the endpoint binds the hashed `liveview_port`. Have `mob_app.ex` set `:host_url` to `http://127.0.0.1:#{liveview_port}/` (Step 6 fix #1). |
| WebView: `FunctionClauseError` in `Access.get(false, :patterns, …)` | `mob_app.ex` sets `live_reload: false`; `Phoenix.LiveReloader` needs a keyword list. Use `live_reload: [patterns: []]` (Step 6 fix #2). |
| Page renders unstyled; `/assets/*` 404 | Frontend assets weren't built. Run `mix assets.build` before `mix mob.deploy --native` (Step 6 fix #3). |
| App launches but WebView shows error page | Local Phoenix endpoint isn't up. The default `mob_app.ex` (LV mode) boots Phoenix on-device. Check `Logcat` for crash logs. |
| `window.mob` is undefined in the WebView | Native shell didn't inject. Re-run `mix mob.deploy --native` and look for build errors. |

---

## Out of scope for this demo

- Custom app icons (run `mix mob.install` again with a `priv/static/icon.png` in place)
- Push notifications (separate setup)
- App store / Play Store submission
- Multi-environment configuration (dev vs prod URLs)
- Hologram / non-LV bridge modes (use `mix mob.adopt --no-live-view` instead)
- The thin-client `--host-url` mode (covered separately in
  [`scrawly-thin-client-mob-plan.md`](scrawly-thin-client-mob-plan.md))

The point is to prove the install path works and the bridge is live.
Anything more is normal Mob usage.
