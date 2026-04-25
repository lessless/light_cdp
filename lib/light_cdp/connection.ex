defmodule LightCDP.Connection do
  @moduledoc """
  WebSocket client for the Chrome DevTools Protocol.

  Manages a single WebSocket connection to a CDP endpoint, dispatching
  commands with auto-incrementing IDs and routing responses/events back
  to callers.

  Typically not used directly — `LightCDP.start/1` handles connection setup.

  ## Low-level usage

      {:ok, conn} = LightCDP.Connection.open("http://127.0.0.1:9222")
      {:ok, result} = LightCDP.Connection.send_command(conn, "Browser.getVersion")
      LightCDP.Connection.close(conn)
  """

  use WebSockex

  @doc """
  Connects to a CDP endpoint.

  Fetches the WebSocket URL from `{endpoint}/json/version`, then opens
  a WebSocket connection.

  Returns `{:ok, pid}` or `{:error, %LightCDP.ConnectionError{}}`.
  """
  def open(endpoint) do
    case Req.get(endpoint <> "/json/version", retry: false) do
      {:ok, %{body: %{"webSocketDebuggerUrl" => ws_url}}} ->
        WebSockex.start_link(ws_url, __MODULE__, %{
          id: 1,
          pending: %{},
          event_waiters: %{}
        })

      {:ok, resp} ->
        {:error, LightCDP.ConnectionError.new({:unexpected_response, resp.status})}

      {:error, reason} ->
        {:error, LightCDP.ConnectionError.new(reason)}
    end
  end

  @doc """
  Closes the WebSocket connection.
  """
  def close(pid) do
    Process.unlink(pid)
    Process.exit(pid, :normal)
    :ok
  end

  @doc """
  Sends a CDP command and waits for the response.

  Returns `{:ok, result}`, `{:error, %LightCDP.CDPError{}}`, or
  `{:error, %LightCDP.TimeoutError{}}`.

  `session_id` is required for commands targeting a specific page/target
  (anything after `Target.attachToTarget`).
  """
  def send_command(pid, method, params \\ %{}, timeout \\ 15_000, session_id \\ nil) do
    metadata = %{method: method, session_id: session_id}

    :telemetry.span([:light_cdp, :connection, :command], metadata, fn ->
      ref = make_ref()
      WebSockex.cast(pid, {:send_command, method, params, session_id, self(), ref})

      result =
        receive do
          {:cdp_response, ^ref, result} ->
            {:ok, result}

          {:cdp_error, ^ref, %{"code" => code, "message" => message}} ->
            {:error, LightCDP.CDPError.new(code, message)}

          {:cdp_error, ^ref, error} ->
            {:error, LightCDP.CDPError.new(0, inspect(error))}
        after
          timeout -> {:error, LightCDP.TimeoutError.new(operation: method, timeout_ms: timeout)}
        end

      {result, metadata}
    end)
  end

  @doc """
  Waits for a CDP event by method name.

  Combines `register_event_waiter/2` and `await_event/2`.
  """
  def wait_for_event(pid, method, timeout \\ 15_000) do
    ref = register_event_waiter(pid, method)
    await_event(ref, timeout)
  end

  @doc """
  Registers a waiter for a CDP event. Returns a ref to pass to `await_event/2`.

  Register **before** triggering the action that produces the event to
  avoid race conditions.
  """
  def register_event_waiter(pid, method) do
    ref = make_ref()
    WebSockex.cast(pid, {:wait_event, method, self(), ref})
    ref
  end

  @doc """
  Blocks until the event registered with `register_event_waiter/2` fires.

  Returns `{:ok, params}` or `{:error, %LightCDP.TimeoutError{}}`.
  """
  def await_event(ref, timeout \\ 15_000) do
    receive do
      {:cdp_event, ^ref, params} -> {:ok, params}
    after
      timeout -> {:error, LightCDP.TimeoutError.new(operation: :await_event, timeout_ms: timeout)}
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

    {:reply, {:text, msg}, %{state | id: id + 1, pending: Map.put(state.pending, id, {from, ref})}}
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
