// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/phoenix_adopt_mob_demo"
import topbar from "../vendor/topbar"

// MobHook — Mob LiveView bridge. Added by `mix mob.new --liveview`.
//
// WHY THIS EXISTS: The native WebView injects window.mob pointing at the NIF
// bridge (postMessage on iOS, JavascriptInterface on Android). In LiveView
// mode we want window.mob to route through the LiveView WebSocket instead so
// handle_event/3 in your LiveView receives JS messages and push_event/3
// delivers server messages back to JS.
//
// This hook replaces window.mob on mount. It requires a DOM element with
// phx-hook="MobHook" — see root.html.heex. Without that element this hook
// never runs and messages silently use the native bridge instead.
const MobHook = {
  mounted() {
    window.mob = {
      // JS → LiveView: arrives as handle_event("mob_message", data, socket)
      send: (data) => this.pushEvent("mob_message", data),
      // LiveView → JS: push_event(socket, "mob_push", data) calls all handlers
      onMessage: (handler) => this.handleEvent("mob_push", handler),
      // No-op in LiveView mode. The native bridge calls this to deliver
      // webview_post_message results, but in LiveView mode server messages
      // arrive via handleEvent("mob_push") instead.
      _dispatch: () => {}
    }
  }
}

// Demo hook: buzz the phone (see DemoLive). In mob's LiveView-bridge mode,
// window.mob.send is defined as `(data) => this.pushEvent("mob_message", data)`.
// We push that same event directly from this in-view hook, which routes
// reliably to handle_event("mob_message", ...) in DemoLive.
//
// Why not call window.mob.send here? The global window.mob installed by MobHook
// lives on #mob-bridge in root.html.heex, which sits OUTSIDE the LiveView
// container in Phoenix 1.8's layout model — so its pushEvent never reaches the
// page LiveView (verified in the browser). An in-view hook's pushEvent does.
const VibrateBtn = {
  mounted() {
    this.el.addEventListener("click", () => {
      this.pushEvent("mob_message", {action: "vibrate"})
    })
  }
}


const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {MobHook, VibrateBtn, ...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
