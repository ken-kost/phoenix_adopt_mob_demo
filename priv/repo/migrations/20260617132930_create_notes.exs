defmodule PhoenixAdoptMobDemo.Repo.Migrations.CreateNotes do
  use Ecto.Migration

  def change do
    create table(:notes) do
      add :body, :string, null: false
      timestamps(type: :utc_datetime)
    end
  end
end
