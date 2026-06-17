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
cd /tmp                # or wherever you keep throwaway projects
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

> **Known rough edge — `--no-ecto` projects.** The default `mob.adopt`
> template for `mob_app.ex` assumes the host has Ecto + `ecto_sqlite3`
> (Mob's on-device SQLite story): it calls
> `Application.ensure_all_started(:ecto_sqlite3)` and runs
> `Ecto.Migrator` against `<App>.Repo`. On a `--no-ecto` project (like
> this demo) those modules don't exist — `mix compile` emits
> `Ecto.Migrator is undefined` warnings and the on-device boot would
> crash at `ensure_all_started(:ecto_sqlite3)`. Fix: delete the
> `ecto_sqlite3` start, the `Ecto.Migrator.with_repo(...)` block, and
> the `migrations_dir/0` helper from the generated `mob_app.ex`. After
> trimming, `mix compile` is clean and the app boots DB-free. (The
> adopt template should detect `--no-ecto` and skip these — tracked as
> a mob_new follow-up.)

---

## Step 4 — Run mob_dev's first-run setup

Different task — same name, different owner. `mob.install` is shipped
by `:mob_dev` (which `mob.adopt` just added to your deps). Runs once
per device. It downloads the OTP runtime tarball, sets up signing,
generates an app icon, etc.

```bash
mix mob.install
```

Follow the prompts. The defaults are fine for a demo.

---

## Step 5 — Local configuration

### `mob.exs`

The `mob.adopt` task seeded `mob.exs` with placeholder paths. Edit
to point at your machine's `mob` checkout (or leave the Hex defaults
if not using local mob):

```elixir
# mob.exs
import Config
config :mob_dev,
  mob_dir: "/home/you/code/mob",
  elixir_lib: "/home/you/.asdf/installs/elixir/1.19.0-otp-28/lib"
```

### Android SDK

```ini
# android/local.properties
sdk.dir=/home/you/Android/Sdk          # Linux
# sdk.dir=/Users/you/Library/Android/sdk  # macOS
```

---

## Step 6 — Deploy to device

Start your Android emulator first (or plug in a physical device with
USB debugging enabled). Then:

```bash
mix mob.deploy --native
```

First build is slow (~3–5 min) — it's compiling the native shell,
packaging the BEAM, building the APK, and signing. Subsequent
deploys (without `--native`) skip the native rebuild and just push
the changed BEAMs (~2–3 sec).

When the build finishes, the app launches on the device. You should
see the Phoenix LiveView welcome page rendered inside the WebView.

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
deployed app:

- [ ] Welcome page renders (Phoenix's standard `PageController.home`)
- [ ] LiveView socket connects (no "disconnected" banner)
- [ ] Refresh / navigation works
- [ ] In the WebView devtools console (Safari Web Inspector for iOS,
      `chrome://inspect` for Android Chrome):
      ```javascript
      typeof window.mob   // → "object"
      ```
      That's the native bridge injection. If it's `"undefined"`, the
      native shell didn't inject — re-run `mix mob.deploy --native`
      and check the Logcat / device console for errors.

At this point you've proven `mob.adopt` works end-to-end on the
blessed shape. Steps 8–9 below are the "wow factor" — feel free to
stop here if you just wanted to confirm the install path.

---

## Step 8 — Native interaction #1: vibrate on tap

Tiny but visceral. Add a button to the stock Phoenix LV welcome page
that buzzes the phone via the native bridge.

Edit `lib/phoenix_adopt_mob_demo_web/controllers/page_html/home.html.heex` (or
wherever the home page renders) and append:

```heex
<button
  id="vibrate-btn"
  phx-hook="VibrateBtn"
  class="rounded bg-zinc-900 px-4 py-2 text-white"
>
  Buzz the phone
</button>
```

In `assets/js/app.js`, after the existing `MobHook` definition, add
a tiny hook that calls into the native bridge:

```javascript
const VibrateBtn = {
  mounted() {
    this.el.addEventListener("click", () => {
      // The exact bridge call depends on mob's runtime API.
      // Check `mob_dev`'s docs for the canonical vibrate function;
      // the pattern is always: `window.mob.<something>(...)`.
      if (window.mob && window.mob.vibrate) {
        window.mob.vibrate(120)            // 120 ms buzz
      } else {
        // Fallback: send a generic message and let BEAM handle it.
        window.mob.send({op: "vibrate", ms: 120})
      }
    })
  }
}
```

Register the hook in the existing `LiveSocket` initialiser (alongside
`MobHook`):

```javascript
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { MobHook, VibrateBtn },    // ← add VibrateBtn
  params: { _csrf_token: csrfToken }
})
```

Redeploy (Phoenix-only change — no native rebuild needed):

```bash
mix mob.deploy
```

Tap the button. The phone buzzes.

---

## Step 9 — Native interaction #2: native toast / native alert

Even simpler — call a native dialog from JS so you see the platform's
own UI render on top of the WebView.

```heex
<button
  id="toast-btn"
  phx-hook="ToastBtn"
  class="rounded bg-emerald-700 px-4 py-2 text-white"
>
  Show a native toast
</button>
```

```javascript
const ToastBtn = {
  mounted() {
    this.el.addEventListener("click", () => {
      // Again — exact API per mob_dev docs. Common shapes:
      //   window.mob.toast("Hello from native")
      //   window.mob.send({op: "toast", message: "Hello"})
      if (window.mob && window.mob.toast) {
        window.mob.toast("Hello from native!")
      } else {
        window.mob.send({op: "toast", message: "Hello from native!"})
      }
    })
  }
}

// Register ToastBtn alongside MobHook + VibrateBtn in LiveSocket hooks.
```

Redeploy with `mix mob.deploy`, tap the button. A platform-native
toast (Android) or alert (iOS) appears.

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

---

## Troubleshooting cheatsheet

| Symptom | Cause / fix |
|---|---|
| `task "mob.adopt" could not be found` | `mob_new` archive isn't installed. `mix archive.install hex mob_new`. |
| `mob.adopt requires a Phoenix project` | The target's `mix.exs` doesn't have `:phoenix` in deps. Confirm `mix phx.new` ran successfully. |
| `requires a stock new LiveSocket(...)` | The project's `assets/js/app.js` isn't shaped like `mix phx.new`'s output. Either restore the stock file or use `mix mob.adopt --no-live-view` (thin-client mode). |
| `requires a <body> tag in root.html.heex` | Same idea — heavily customised root layout. Restore the stock layout or use `--no-live-view`. |
| `mix compile` fails after adopt | The generated `mob_app.ex` referenced a Mob module that isn't in your `:mob` version. Check Mob's CHANGELOG for breaking changes since `mob_new`'s template. |
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
