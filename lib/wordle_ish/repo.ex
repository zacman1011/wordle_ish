defmodule WordleIsh.Repo do
  use Ecto.Repo,
    otp_app: :wordle_ish,
    adapter: Ecto.Adapters.Postgres
end
