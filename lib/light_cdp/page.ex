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

  def content(%__MODULE__{conn: conn, session_id: sid}) do
    with {:ok, %{"root" => %{"nodeId" => root_id}}} <-
           send_cdp(conn, sid, "DOM.getDocument"),
         {:ok, %{"outerHTML" => html}} <-
           send_cdp(conn, sid, "DOM.getOuterHTML", %{nodeId: root_id}) do
      {:ok, html}
    end
  end

  def click(%__MODULE__{} = page, selector, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout

    with {:ok, node_id} <- query_selector(page, selector, timeout),
         {:ok, {x, y}} <- get_click_point(page, node_id, timeout) do
      dispatch_click(page, x, y, timeout)
    end
  end

  def fill(%__MODULE__{} = page, selector, value, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout

    with {:ok, node_id} <- query_selector(page, selector, timeout),
         {:ok, object_id} <- resolve_node(page, node_id, timeout),
         :ok <- focus_element(page, object_id, timeout),
         :ok <- clear_value(page, object_id, timeout),
         :ok <- insert_text(page, value, timeout) do
      :ok
    end
  end

  def submit(page, form_selector, fields \\ %{}, opts \\ []) do
    with :ok <- fill_fields(page, fields, opts) do
      wait_for_navigation(page, fn ->
        evaluate(page, """
        (() => {
          const form = document.querySelector(#{Jason.encode!(form_selector)});
          if (!form) throw new Error('Form not found: #{form_selector}');
          form.submit();
        })()
        """)
      end, opts)
    end
  end

  def wait_for_navigation(%__MODULE__{conn: conn}, fun, opts \\ []) do
    timeout = opts[:timeout] || @nav_timeout
    wait_ref = LightCDP.Connection.register_event_waiter(conn, "Page.loadEventFired")

    case fun.() do
      {:error, _} = err ->
        err

      _ ->
        case LightCDP.Connection.await_event(wait_ref, timeout) do
          {:ok, _} -> :ok
          {:error, _} = err -> err
        end
    end
  end

  # --- Native CDP helpers ---

  defp query_selector(%{conn: conn, session_id: sid}, selector, timeout) do
    with {:ok, %{"root" => %{"nodeId" => root_id}}} <-
           send_cdp(conn, sid, "DOM.getDocument", %{}, timeout),
         {:ok, %{"nodeId" => node_id}} <-
           send_cdp(conn, sid, "DOM.querySelector", %{nodeId: root_id, selector: selector}, timeout) do
      if node_id == 0 do
        {:error, "Element not found: #{selector}"}
      else
        {:ok, node_id}
      end
    end
  end

  defp get_click_point(%{conn: conn, session_id: sid}, node_id, timeout) do
    with {:ok, %{"model" => %{"content" => quad}}} <-
           send_cdp(conn, sid, "DOM.getBoxModel", %{nodeId: node_id}, timeout) do
      [x1, y1, x2, y2, x3, y3, x4, y4] = quad
      {:ok, {(x1 + x2 + x3 + x4) / 4, (y1 + y2 + y3 + y4) / 4}}
    end
  end

  defp dispatch_click(%{conn: conn, session_id: sid}, x, y, timeout) do
    mouse = fn type ->
      send_cdp(conn, sid, "Input.dispatchMouseEvent", %{
        type: type, x: x, y: y, button: "left", clickCount: 1
      }, timeout)
    end

    with {:ok, _} <- mouse.("mousePressed"),
         {:ok, _} <- mouse.("mouseReleased") do
      :ok
    end
  end

  defp resolve_node(%{conn: conn, session_id: sid}, node_id, timeout) do
    with {:ok, %{"object" => %{"objectId" => object_id}}} <-
           send_cdp(conn, sid, "DOM.resolveNode", %{nodeId: node_id}, timeout) do
      {:ok, object_id}
    end
  end

  defp focus_element(%{conn: conn, session_id: sid}, object_id, timeout) do
    with {:ok, _} <-
           send_cdp(conn, sid, "Runtime.callFunctionOn", %{
             objectId: object_id,
             functionDeclaration: "function() { this.focus(); }"
           }, timeout) do
      :ok
    end
  end

  defp clear_value(%{conn: conn, session_id: sid}, object_id, timeout) do
    with {:ok, _} <-
           send_cdp(conn, sid, "Runtime.callFunctionOn", %{
             objectId: object_id,
             functionDeclaration: "function() { this.value = ''; }"
           }, timeout) do
      :ok
    end
  end

  defp insert_text(%{conn: conn, session_id: sid}, value, timeout) do
    with {:ok, _} <- send_cdp(conn, sid, "Input.insertText", %{text: value}, timeout) do
      :ok
    end
  end

  defp send_cdp(conn, sid, method, params \\ %{}, timeout \\ @default_timeout) do
    LightCDP.Connection.send_command(conn, method, params, timeout, sid)
  end

  defp fill_fields(_page, fields, _opts) when map_size(fields) == 0, do: :ok

  defp fill_fields(page, fields, opts) do
    Enum.reduce_while(fields, :ok, fn {selector, value}, :ok ->
      case fill(page, selector, value, opts) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
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
