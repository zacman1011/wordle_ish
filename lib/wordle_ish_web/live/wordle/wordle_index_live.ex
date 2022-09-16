defmodule WordleIsh.Wordle.WordleIndexLive do
  use WordleIshWeb, :live_view

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {
      :ok,
      assign(
        socket,
        word: "happy"
      )
    }
  end
end
