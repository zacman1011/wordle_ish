defmodule WordleIsh.Wordle.WordleIndexLive do
  use WordleIshWeb, :live_view

  require Logger

  @default_colour "bg-gray-900"
  @wrong_letter "bg-gray-400"
  @misplaced_letter "bg-yellow-400"
  @correct_letter "bg-green-400"

  @error_timer 3000

  @impl true
  def mount(_params, _session, socket) do
    word = "happy"
    word_length = String.length(word)
    {word_graphemes, _} = Enum.reduce(String.graphemes(word), {%{}, 1}, fn(c, {acc, n}) -> {Map.put(acc, n, c), n+1} end)
    letter_map = Enum.reduce(word_graphemes, %{}, fn({_, c}, acc) ->
      Map.update(acc, c, 1, &(&1 + 1))
    end)

    guess_row = Enum.into(1..word_length, %{}, fn(num) -> {num, %{colour: @default_colour, character: ""}} end)
    guess_matrix = Enum.into(1..table_length(word_length), %{}, fn(num) -> {num, guess_row} end)

    {
      :ok,
      assign(
        socket,
        word:            word,
        word_graphemes:  word_graphemes,
        word_length:     word_length,
        guess_matrix:    guess_matrix,
        letter_map:      letter_map,
        curr_row:        1,
        letters_entered: 0,
        correct?:        false,
        error:           nil,
        error_timer:     nil
      )
    }
  end

  @impl true
  def handle_event("letter_press", %{"key" => "Enter"}, socket) do
    word_length = socket.assigns.word_length
    letters_entered = socket.assigns.letters_entered
    correct? = socket.assigns.correct?

    socket = case {letters_entered, correct?} do
      {^word_length, false} ->
        do_user_attempt(socket)

      {_, true} ->
        socket

      {_, _} ->
        error_occurred("Not enough letters entered. Must be exactly #{word_length}", socket)
    end

    {:noreply, socket}
  end
  def handle_event("letter_press", %{"key" => "Backspace"}, socket) do
    socket = unless socket.assigns.correct?, do: do_backspace(socket), else: socket
    {:noreply, socket}
  end
  def handle_event("letter_press", %{"key" => letter}, socket) do
    socket = if letter =~ ~r{^[a-zA-Z]$} and not socket.assigns.correct? do
      do_letter_pressed(letter, socket)
    else
      socket
    end

    {:noreply, socket}
  end
  def handle_event(event, params, socket) do
    Logger.warn("Unknown event: #{inspect event} -- #{inspect params, pretty: true}")
    {:noreply, socket}
  end

  @impl true
  def handle_info({:error, error}, socket) do
    curr_error = socket.assigns.error

    socket = if error == curr_error do
      assign(socket, :error, nil)
    else
      socket
    end

    {:noreply, socket}
  end

  defp do_user_attempt(socket) do
    guess_matrix = socket.assigns.guess_matrix
    curr_row = socket.assigns.curr_row
    word_graphemes = socket.assigns.word_graphemes
    letter_map = socket.assigns.letter_map

    current_guess = guess_matrix[curr_row]

    {current_guess, correct?} = make_guess(current_guess, word_graphemes, letter_map)

    socket
      |> assign(:guess_matrix, Map.put(guess_matrix, curr_row, current_guess))
      |> assign(:letters_entered, 0)
      |> assign(:correct?, correct?)
      |> update(:curr_row, &(&1 + 1))
  end

  defp make_guess(current_guess, word_graphemes, letter_map) do
    {current_guess, letter_map} = Enum.reduce(current_guess, {%{}, letter_map}, fn({num_place, %{character: character}}, {acc, letter_map}) ->
      if character == word_graphemes[num_place] do
        {
          Map.put(acc, num_place, %{character: character, colour: @correct_letter}),
          Map.update!(letter_map, character, fn(n) -> n - 1 end)
        }
      else
        {
          Map.put(acc, num_place, %{character: character, colour: @default_colour}),
          letter_map
        }
      end
    end)

    {current_guess, _} = Enum.reduce(current_guess, {%{}, letter_map}, fn({num_place, %{character: character, colour: colour}}, {acc, letter_map}) ->
      correct_colour = @correct_letter
      case {colour, Map.fetch(letter_map, character)} do
        {^correct_colour, _} ->
          {Map.put(acc, num_place, %{colour: @correct_letter, character: character}), letter_map}

        {_, {:ok, 0}} ->
          {Map.put(acc, num_place, %{colour: @wrong_letter, character: character}), letter_map}

        {_, {:ok, _}} ->
          {
            Map.put(acc, num_place, %{colour: @misplaced_letter, character: character}),
            Map.update!(letter_map, character, fn(n) -> n - 1 end)
          }

        {_, :error} ->
          {Map.put(acc, num_place, %{colour: @wrong_letter, character: character}), letter_map}
      end
    end)

    {current_guess, not Enum.any?(current_guess, fn({_, %{colour: c}}) -> c != @correct_letter end)}
  end

  defp do_backspace(socket) do
    letters_entered = socket.assigns.letters_entered
    curr_row = socket.assigns.curr_row

    unless letters_entered == 0 do
      socket
        |> assign(:letters_entered, letters_entered - 1)
        |> update(:guess_matrix, fn(guess_matrix) ->
          Map.update!(guess_matrix, curr_row, fn(guess_row) ->
            Map.delete(guess_row, letters_entered)
          end)
        end)
    else
      socket
    end
  end

  defp do_letter_pressed(letter, socket) do
    letters_entered = socket.assigns.letters_entered
    word_length = socket.assigns.word_length
    curr_row = socket.assigns.curr_row

    unless letters_entered == word_length do
      letters_entered = letters_entered + 1
      socket
        |> assign(:letters_entered, letters_entered)
        |> update(:guess_matrix, fn(guess_matrix) ->
          Map.update!(guess_matrix, curr_row, fn(guess_row) ->
            Map.put(guess_row, letters_entered, %{character: letter, colour: @default_colour})
          end)
        end)
    else
      socket
    end
  end

  defp error_occurred(error, socket) do
    timer = Process.send_after(self(), {:error_remove, error}, @error_timer)
    assign(socket, error: error, error_timer: timer)
  end

  def wordle_show_table(assigns) do
    ~H"""
      <div class="grid grid-cols-1 w-96 gap-y-2">
        <%= for row <- 1..table_length(@word_length) do %>
          <.wordle_show_row word_length={@word_length} guess_matrix={@guess_matrix} row={row} />
        <% end %>
      </div>
    """
  end

  def wordle_show_row(assigns) do
    ~H"""
      <div class={table_width(@word_length)}>
        <%= for column <- 1..5 do %>
          <div class={character_box_class(@guess_matrix[@row][column][:colour])}>
            <%= @guess_matrix[@row][column][:character] %>
          </div>
        <% end %>
      </div>
    """
  end

  defp table_width(number) do
    "grid grid-cols-#{number} gap-x-2"
  end

  defp character_box_class(colour) do
    "border-2 border-gray-500 h-16 w-16 text-center text-5xl text-gray-300 #{colour}"
  end

  defp table_length(number), do: number + 1

  def keyboard(assigns) do
    ~H"""
      <div class="w-full grid grid-cols-20 gap-2">
        <.keyboard_letter_row_start character={"Q"} start={1} />
        <.keyboard_letter character={"W"} />
        <.keyboard_letter character={"E"} />
        <.keyboard_letter character={"R"} />
        <.keyboard_letter character={"T"} />
        <.keyboard_letter character={"Y"} />
        <.keyboard_letter character={"U"} />
        <.keyboard_letter character={"I"} />
        <.keyboard_letter character={"O"} />
        <.keyboard_letter character={"P"} />
        <.keyboard_letter_row_start character={"A"} start={2} />
        <.keyboard_letter character={"S"} />
        <.keyboard_letter character={"D"} />
        <.keyboard_letter character={"F"} />
        <.keyboard_letter character={"G"} />
        <.keyboard_letter character={"H"} />
        <.keyboard_letter character={"J"} />
        <.keyboard_letter character={"K"} />
        <.keyboard_letter character={"L"} />
        <.enter_key />
        <.keyboard_letter character={"Z"} />
        <.keyboard_letter character={"X"} />
        <.keyboard_letter character={"C"} />
        <.keyboard_letter character={"V"} />
        <.keyboard_letter character={"B"} />
        <.keyboard_letter character={"N"} />
        <.keyboard_letter character={"M"} />
        <.backspace_key />
      </div>
    """
  end

  def enter_key(assigns) do
    ~H"""
      <div class="text-3xl text-gray-300 col-span-2 text-center border-2 border-gray-300">
        <button class="w-full h-full" phx-click="letter_press" phx-value-key="Enter">
          Enter
        </button>
      </div>
    """
  end

  def backspace_key(assigns) do
    ~H"""
      <div class="text-3xl text-gray-300 col-span-2 text-center flex items-center justify-center border-2 border-gray-300">
        <button class="w-full h-full flex items-center justify-center" phx-click="letter_press" phx-value-key="Backspace">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 9.75L14.25 12m0 0l2.25 2.25M14.25 12l2.25-2.25M14.25 12L12 14.25m-2.58 4.92l-6.375-6.375a1.125 1.125 0 010-1.59L9.42 4.83c.211-.211.498-.33.796-.33H19.5a2.25 2.25 0 012.25 2.25v10.5a2.25 2.25 0 01-2.25 2.25h-9.284c-.298 0-.585-.119-.796-.33z" />
          </svg>
        </button>
      </div>
    """
  end

  def keyboard_letter_row_start(assigns) do
    ~H"""
      <div class={keyboard_letter_class(@start)}>
        <button class="w-full h-full" phx-click="letter_press" phx-value-key={@character}>
          <%= @character %>
        </button>
      </div>
    """
  end

  def keyboard_letter(assigns) do
    ~H"""
      <div class="text-3xl text-gray-300 col-span-2 border-2 border-gray-300">
        <button class="w-full h-full" phx-click="letter_press" phx-value-key={@character}>
          <%= @character %>
        </button>
      </div>
    """
  end

  defp keyboard_letter_class(start) do
    "text-3xl text-gray-300 col-start-#{start} col-end-#{start+2} border-2 border-gray-300"
  end
end
