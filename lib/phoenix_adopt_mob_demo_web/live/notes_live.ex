defmodule PhoenixAdoptMobDemoWeb.NotesLive do
  @moduledoc """
  A tiny persisted Notes CRUD that proves end-to-end DB persistence: Postgres
  when run as a normal Phoenix server, SQLite when it runs on the device. Notes
  survive refresh/reconnect because they live in a database, not socket state.
  """
  use PhoenixAdoptMobDemoWeb, :live_view

  alias PhoenixAdoptMobDemo.Notes

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Notes") |> assign_form() |> load()}
  end

  @impl true
  def handle_event("save", %{"note" => params}, socket) do
    case Notes.create_note(params) do
      {:ok, _note} ->
        {:noreply, socket |> put_flash(:info, "Saved.") |> assign_form() |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp assign_form(socket), do: assign(socket, form: to_form(Notes.change_note()))
  defp load(socket), do: assign(socket, notes: Notes.list_notes())

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Notes
        <:subtitle>
          Postgres on the server, SQLite on-device — same code, same migration.
        </:subtitle>
      </.header>

      <.form for={@form} id="note-form" phx-submit="save" class="mt-6 flex gap-2">
        <div class="flex-1">
          <.input field={@form[:body]} type="text" placeholder="Write a note…" />
        </div>
        <.button>Save</.button>
      </.form>

      <ul id="notes" class="mt-8 divide-y divide-base-200">
        <li :for={note <- @notes} id={"note-#{note.id}"} class="py-3">{note.body}</li>
        <li :if={@notes == []} class="py-3 text-base-content/50">
          No notes yet — add one; it survives a refresh.
        </li>
      </ul>

      <.link
        navigate={~p"/"}
        class="mt-8 inline-block text-sm text-base-content/70 hover:text-base-content"
      >
        ← Back home
      </.link>
    </Layouts.app>
    """
  end
end
