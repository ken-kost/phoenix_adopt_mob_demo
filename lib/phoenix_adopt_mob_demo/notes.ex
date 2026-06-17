defmodule PhoenixAdoptMobDemo.Notes do
  @moduledoc """
  The Notes context.

  Every query goes through the *active* repo — `Application.get_env(:repo)` —
  so the exact same code persists to Postgres when run as a server and to the
  on-device SQLite `LocalRepo` in the Mob build. The repo is selected by the
  supervision tree (Postgres default) and flipped to SQLite by `mob_app.ex`
  before boot. See the "Database persistence" section of the demo plan.
  """
  import Ecto.Query, warn: false
  alias PhoenixAdoptMobDemo.Notes.Note

  defp repo,
    do: Application.get_env(:phoenix_adopt_mob_demo, :repo, PhoenixAdoptMobDemo.Repo)

  @doc "List notes, newest first."
  def list_notes, do: repo().all(from(n in Note, order_by: [desc: n.inserted_at]))

  @doc "Build a changeset for a (new or existing) note."
  def change_note(note \\ %Note{}, attrs \\ %{}), do: Note.changeset(note, attrs)

  @doc "Insert a note from user params."
  def create_note(attrs) do
    %Note{} |> Note.changeset(attrs) |> repo().insert()
  end
end
