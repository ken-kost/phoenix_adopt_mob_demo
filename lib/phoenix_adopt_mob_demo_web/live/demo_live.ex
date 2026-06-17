defmodule PhoenixAdoptMobDemoWeb.DemoLive do
  @moduledoc """
  Native-bridge demo page.

  Each button pushes a `"mob_message"` event to this LiveView — the same event
  `window.mob.send/1` emits in mob's LiveView-bridge mode (it is literally
  `this.pushEvent("mob_message", data)`). `handle_event("mob_message", _, socket)`
  below receives it and, on a device, fires a real native effect (haptic buzz,
  native toast). In a plain browser the native NIF is not loaded, so we guard
  the call with `native?/0` and surface the round-trip as on-page feedback
  instead — which is what makes this page verifiable without a device: the
  JS → LiveView round-trip still happens, we just skip the on-device-only NIF.
  """
  use PhoenixAdoptMobDemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, events: [], page_title: "Native bridge demo")}
  end

  @impl true
  def handle_event("mob_message", %{"action" => "vibrate"}, socket) do
    if native?(), do: Mob.Haptic.trigger(socket, :medium)
    {:noreply, log(socket, "📳 vibrate → Mob.Haptic.trigger(:medium)")}
  end

  def handle_event("mob_message", %{"action" => "toast", "message" => message}, socket) do
    if native?(), do: Mob.Alert.toast(socket, message)
    {:noreply, log(socket, "🔔 toast → Mob.Alert.toast(#{inspect(message)})")}
  end

  # Catch-all so an unhandled bridge message can never crash the LiveView.
  def handle_event("mob_message", _payload, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Native bridge demo
        <:subtitle>
          Each button pushes a <code class="text-sm">"mob_message"</code>
          event — the
          same one <code class="text-sm">window.mob.send/1</code>
          emits — to <code class="text-sm">handle_event/3</code>. On a device it fires a native
          effect; here it logs the round-trip below.
        </:subtitle>
      </.header>

      <div class="mt-8 flex flex-wrap gap-3">
        <button
          id="vibrate-btn"
          phx-hook="VibrateBtn"
          class="rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white hover:bg-zinc-700"
        >
          Buzz the phone
        </button>
        <button
          id="toast-btn"
          phx-hook="ToastBtn"
          class="rounded-lg bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-600"
        >
          Show a native toast
        </button>
      </div>

      <div class="mt-8">
        <h2 class="text-sm font-semibold text-base-content/70">Bridge round-trips</h2>
        <ul
          id="event-log"
          class="mt-2 divide-y divide-base-200 rounded-lg border border-base-200"
        >
          <li
            :for={{event, i} <- Enum.with_index(@events)}
            id={"event-#{i}"}
            class="px-4 py-2 font-mono text-sm"
          >
            {event}
          </li>
          <li :if={@events == []} class="px-4 py-2 text-sm text-base-content/50">
            Tap a button — the message round-trips through the bridge and shows up here.
          </li>
        </ul>
      </div>

      <.link
        navigate={~p"/"}
        class="mt-8 inline-block text-sm text-base-content/70 hover:text-base-content"
      >
        ← Back home
      </.link>
    </Layouts.app>
    """
  end

  # Keep the most recent few round-trips, newest first.
  defp log(socket, message) do
    update(socket, :events, fn events -> Enum.take([message | events], 8) end)
  end

  # True only when the Mob native runtime is loaded (i.e. running on a device).
  # Mirrors Mob.App's own `safe_platform/0`: the NIF raises when not loaded.
  defp native? do
    :mob_nif.platform() in [:ios, :android]
  rescue
    _ -> false
  end
end
