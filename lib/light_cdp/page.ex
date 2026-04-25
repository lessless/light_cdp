defmodule LightCDP.Page do
  defstruct [:conn, :session_id]

  def new(conn) do
    {:ok, %{"targetId" => target_id}} =
      LightCDP.Connection.send_command(conn, "Target.createTarget", %{url: "about:blank"})

    {:ok, %{"sessionId" => session_id}} =
      LightCDP.Connection.send_command(conn, "Target.attachToTarget", %{
        targetId: target_id,
        flatten: true
      })

    LightCDP.Connection.send_command(conn, "Page.enable", %{}, 5_000, session_id)

    {:ok, %__MODULE__{conn: conn, session_id: session_id}}
  end

  def navigate(%__MODULE__{conn: conn, session_id: sid}, url) do
    wait_ref = LightCDP.Connection.register_event_waiter(conn, "Page.loadEventFired")

    {:ok, _} =
      LightCDP.Connection.send_command(conn, "Page.navigate", %{url: url}, 30_000, sid)

    LightCDP.Connection.await_event(wait_ref, 30_000)
    :ok
  end

  def evaluate(%__MODULE__{conn: conn, session_id: sid}, expression) do
    {:ok, result} =
      LightCDP.Connection.send_command(
        conn,
        "Runtime.evaluate",
        %{expression: expression, returnByValue: true},
        15_000,
        sid
      )

    case result do
      %{"exceptionDetails" => %{"exception" => %{"description" => desc}}} ->
        {:error, desc}

      %{"exceptionDetails" => details} ->
        {:error, inspect(details)}

      %{"result" => %{"value" => value}} ->
        {:ok, value}

      %{"result" => %{"type" => "undefined"}} ->
        {:ok, nil}

      %{"result" => result_inner} ->
        {:ok, result_inner["value"]}
    end
  end

  def url(page) do
    evaluate(page, "window.location.href")
  end

  def content(page) do
    evaluate(page, "document.documentElement.outerHTML")
  end

  def click(page, selector) do
    case evaluate(page, """
         (() => {
           const el = document.querySelector(#{Jason.encode!(selector)});
           if (!el) throw new Error('Element not found: #{selector}');
           el.click();
         })()
         """) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  def fill(page, selector, value) do
    case evaluate(page, """
         (() => {
           const el = document.querySelector(#{Jason.encode!(selector)});
           if (!el) throw new Error('Element not found: #{selector}');
           el.value = #{Jason.encode!(value)};
           el.dispatchEvent(new Event('input', {bubbles: true}));
           el.dispatchEvent(new Event('change', {bubbles: true}));
         })()
         """) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  def wait_for_navigation(%__MODULE__{conn: conn} = _page, fun) do
    wait_ref = LightCDP.Connection.register_event_waiter(conn, "Page.loadEventFired")
    fun.()
    LightCDP.Connection.await_event(wait_ref, 30_000)
    :ok
  end
end
