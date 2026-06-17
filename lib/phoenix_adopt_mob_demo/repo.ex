defmodule PhoenixAdoptMobDemo.Repo do
  use Ecto.Repo,
    otp_app: :phoenix_adopt_mob_demo,
    adapter: Ecto.Adapters.Postgres
end
