defmodule LightCDP.Page do
  defstruct [:conn, :session_id]

  @default_timeout 15_000
  @nav_timeout 30_000

  def new(conn) do
    with {:ok, %{"targetId" => target_id}} <-
           LightCDP.Connection.send_command(conn, "Target.createTarget", %{url: "about:blank"}),
         {:ok, %{"sessionId" => session_id}} <-
           LightCDP.Connection.send_command(conn, "Target.attachToTarget", %{
             targetId: target_id,
             flatten: true
           }),
         {:ok, _} <-
           LightCDP.Connection.send_command(conn, "Page.enable", %{}, 5_000, session_id) do
      {:ok, %__MODULE__{conn: conn, session_id: session_id}}
    end
  end

  def navigate(%__MODULE__{conn: conn, session_id: sid}, url, opts \\ []) do
    timeout = opts[:timeout] || @nav_timeout
    wait_ref = LightCDP.Connection.register_event_waiter(conn, "Page.loadEventFired")

    with {:ok, _} <-
           LightCDP.Connection.send_command(conn, "Page.navigate", %{url: url}, timeout, sid),
         {:ok, _} <-
           LightCDP.Connection.await_event(wait_ref, timeout) do
      :ok
    end
  end

  def evaluate(%__MODULE__{conn: conn, session_id: sid}, expression, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout

    case LightCDP.Connection.send_command(
           conn,
           "Runtime.evaluate",
           %{expression: expression, returnByValue: true},
           timeout,
           sid
         ) do
      {:ok, result} ->
        parse_evaluate_result(result)

      {:error, _} = err ->
        err
    end
  end

  def url(page) do
    evaluate(page, "window.location.href")
  end

  def content(page) do
    evaluate(page, "document.documentElement.outerHTML")
  end

  def click(page, selector, opts \\ []) do
    case evaluate(
           page,
           """
           (() => {
             const el = document.querySelector(#{Jason.encode!(selector)});
             if (!el) throw new Error('Element not found: #{selector}');
             el.click();
           })()
           """,
           opts
         ) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  def fill(page, selector, value, opts \\ []) do
    case evaluate(
           page,
           """
           (() => {
             const el = document.querySelector(#{Jason.encode!(selector)});
             if (!el) throw new Error('Element not found: #{selector}');
             el.value = #{Jason.encode!(value)};
             el.dispatchEvent(new Event('input', {bubbles: true}));
             el.dispatchEvent(new Event('change', {bubbles: true}));
           })()
           """,
           opts
         ) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  def wait_for_navigation(%__MODULE__{conn: conn}, fun, opts \\ []) do
    timeout = opts[:timeout] || @nav_timeout
    wait_ref = LightCDP.Connection.register_event_waiter(conn, "Page.loadEventFired")
    fun.()

    case LightCDP.Connection.await_event(wait_ref, timeout) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  defp parse_evaluate_result(result) do
    case result do
      %{"exceptionDetails" => %{"exception" => %{"description" => desc}}} ->
        {:error, desc}

      %{"exceptionDetails" => details} ->
        {:error, inspect(details)}

      %{"result" => %{"value" => value}} ->
        {:ok, value}

      %{"result" => %{"type" => "undefined"}} ->
        {:ok, nil}

      %{"result" => inner} ->
        {:ok, inner["value"]}
    end
  end
end
