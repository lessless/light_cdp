defmodule LightCDP.Connection do
  use WebSockex

  def open(endpoint) do
    %{body: %{"webSocketDebuggerUrl" => ws_url}} =
      Req.get!(endpoint <> "/json/version")

    WebSockex.start_link(ws_url, __MODULE__, %{
      id: 1,
      pending: %{},
      event_waiters: %{}
    })
  end

  def close(pid) do
    Process.exit(pid, :normal)
    :ok
  end

  def send_command(pid, method, params \\ %{}, timeout \\ 15_000, session_id \\ nil) do
    ref = make_ref()
    WebSockex.cast(pid, {:send_command, method, params, session_id, self(), ref})

    receive do
      {:cdp_response, ^ref, result} -> {:ok, result}
      {:cdp_error, ^ref, error} -> {:error, error}
    after
      timeout -> {:error, :timeout}
    end
  end

  def wait_for_event(pid, method, timeout \\ 15_000) do
    ref = register_event_waiter(pid, method)
    await_event(ref, timeout)
  end

  def register_event_waiter(pid, method) do
    ref = make_ref()
    WebSockex.cast(pid, {:wait_event, method, self(), ref})
    ref
  end

  def await_event(ref, timeout \\ 15_000) do
    receive do
      {:cdp_event, ^ref, params} -> {:ok, params}
    after
      timeout -> {:error, :timeout}
    end
  end

  # --- WebSockex callbacks ---

  @impl true
  def handle_cast({:send_command, method, params, session_id, from, ref}, state) do
    id = state.id

    msg =
      %{id: id, method: method, params: params}
      |> then(fn m -> if session_id, do: Map.put(m, :sessionId, session_id), else: m end)
      |> Jason.encode!()

    {:reply, {:text, msg},
     %{state | id: id + 1, pending: Map.put(state.pending, id, {from, ref})}}
  end

  @impl true
  def handle_cast({:wait_event, method, from, ref}, state) do
    waiters =
      Map.update(state.event_waiters, method, [{from, ref}], &[{from, ref} | &1])

    {:ok, %{state | event_waiters: waiters}}
  end

  @impl true
  def handle_frame({:text, data}, state) do
    case Jason.decode!(data) do
      %{"id" => id} = msg ->
        case Map.pop(state.pending, id) do
          {{from, ref}, pending} ->
            if msg["error"] do
              send(from, {:cdp_error, ref, msg["error"]})
            else
              send(from, {:cdp_response, ref, msg["result"]})
            end

            {:ok, %{state | pending: pending}}

          {nil, _} ->
            {:ok, state}
        end

      %{"method" => method, "params" => params} ->
        case Map.pop(state.event_waiters, method, []) do
          {[{from, ref} | rest], _} ->
            send(from, {:cdp_event, ref, params})

            waiters =
              if rest == [],
                do: Map.delete(state.event_waiters, method),
                else: Map.put(state.event_waiters, method, rest)

            {:ok, %{state | event_waiters: waiters}}

          {[], _} ->
            {:ok, state}
        end

      _ ->
        {:ok, state}
    end
  end

  @impl true
  def handle_frame(_frame, state), do: {:ok, state}
end
