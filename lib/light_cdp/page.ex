defmodule LightCDP.Page do
  @moduledoc """
  Page interactions via native CDP methods.

  All functions return `{:ok, result}`, `:ok`, or `{:error, exception}` where
  `exception` is one of:

    * `%LightCDP.ElementNotFoundError{}` — selector matched no element
    * `%LightCDP.TimeoutError{}` — operation exceeded its deadline
    * `%LightCDP.JavaScriptError{}` — JS expression threw an exception
    * `%LightCDP.CDPError{}` — CDP protocol error

  ## Native CDP methods used

  | Function           | CDP methods                                                            |
  |--------------------|------------------------------------------------------------------------|
  | `click/3`          | `DOM.querySelector` -> `DOM.getBoxModel` -> `Input.dispatchMouseEvent` |
  | `fill/4`           | `DOM.resolveNode` -> `Runtime.callFunctionOn` -> `Input.insertText`    |
  | `content/1`        | `DOM.getDocument` -> `DOM.getOuterHTML`                                |
  | `navigate/3`       | `Page.navigate` + `Page.loadEventFired` event                         |
  | `evaluate/3`       | `Runtime.evaluate`                                                     |
  | `url/1`            | `Runtime.evaluate` (no native equivalent)                              |
  | `submit/4`         | `Runtime.evaluate` (no native equivalent for form submission)          |

  ## Timeouts

  All functions accept a `timeout:` option in milliseconds.

  | Default        | Functions                                                |
  |----------------|----------------------------------------------------------|
  | 30,000 ms      | `navigate`, `wait_for_navigation`, `submit`              |
  | 15,000 ms      | `evaluate`, `click`, `fill`, `wait_for_selector`         |
  """

  defstruct [:conn, :session_id]

  @default_timeout 15_000
  @nav_timeout 30_000

  @doc false
  def new(conn) do
    with {:ok, %{"targetId" => target_id}} <-
           LightCDP.Connection.send_command(conn, "Target.createTarget", %{url: "about:blank"}),
         {:ok, %{"sessionId" => session_id}} <-
           LightCDP.Connection.send_command(conn, "Target.attachToTarget", %{
             targetId: target_id,
             flatten: true
           }),
         {:ok, _} <-
           LightCDP.Connection.send_command(conn, "Page.enable", %{}, 5_000, session_id),
         {:ok, _} <-
           LightCDP.Connection.send_command(conn, "DOM.enable", %{}, 5_000, session_id) do
      {:ok, %__MODULE__{conn: conn, session_id: session_id}}
    end
  end

  @doc """
  Navigates to `url` and waits for the page to load.

  ## Options

    * `:timeout` - milliseconds (default: `30_000`)

  ## Example

      :ok = LightCDP.Page.navigate(page, "https://example.com")
  """
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

  @doc """
  Evaluates a JavaScript expression and returns the result.

  ## Options

    * `:timeout` - milliseconds (default: `15_000`)

  ## Examples

      {:ok, "Example Domain"} = LightCDP.Page.evaluate(page, "document.title")
      {:ok, 42} = LightCDP.Page.evaluate(page, "21 * 2")
      {:error, %LightCDP.JavaScriptError{}} = LightCDP.Page.evaluate(page, "throw new Error('boom')")
  """
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

  @doc """
  Returns the current page URL.

  ## Example

      {:ok, "https://example.com/"} = LightCDP.Page.url(page)
  """
  def url(page) do
    evaluate(page, "window.location.href")
  end

  @doc """
  Captures a screenshot of the page as a PNG binary.

  Uses native `Page.captureScreenshot`.

  ## Options

    * `:timeout` - milliseconds (default: `15_000`)

  ## Example

      {:ok, png} = LightCDP.Page.screenshot(page)
      File.write!("screenshot.png", png)
  """
  def screenshot(%__MODULE__{conn: conn, session_id: sid}, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout

    with {:ok, %{"data" => data}} <-
           send_cdp(conn, sid, "Page.captureScreenshot", %{format: "png"}, timeout) do
      {:ok, Base.decode64!(data)}
    end
  end

  @doc """
  Returns the full page HTML including doctype.

  Uses native `DOM.getOuterHTML` instead of JavaScript.

  ## Example

      {:ok, html} = LightCDP.Page.content(page)
  """
  def content(%__MODULE__{conn: conn, session_id: sid}) do
    with {:ok, %{"root" => %{"nodeId" => root_id}}} <-
           send_cdp(conn, sid, "DOM.getDocument"),
         {:ok, %{"outerHTML" => html}} <-
           send_cdp(conn, sid, "DOM.getOuterHTML", %{nodeId: root_id}) do
      {:ok, html}
    end
  end

  @doc """
  Clicks an element matching `selector`.

  Uses native CDP: finds the element via `DOM.querySelector`, computes its
  center point from `DOM.getBoxModel`, and dispatches mouse events via
  `Input.dispatchMouseEvent`.

  ## Options

    * `:timeout` - milliseconds (default: `15_000`)

  ## Example

      :ok = LightCDP.Page.click(page, "#submit-btn")
      {:error, %LightCDP.ElementNotFoundError{selector: "#nope"}} = LightCDP.Page.click(page, "#nope")
  """
  def click(%__MODULE__{} = page, selector, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout

    with {:ok, node_id} <- query_selector(page, selector, timeout),
         {:ok, {x, y}} <- get_click_point(page, node_id, timeout) do
      dispatch_click(page, x, y, timeout)
    end
  end

  @doc """
  Fills an input element matching `selector` with `value`.

  Uses native CDP: resolves the DOM node, focuses it via
  `Runtime.callFunctionOn`, clears existing content, then types
  via `Input.insertText`.

  ## Options

    * `:timeout` - milliseconds (default: `15_000`)

  ## Example

      :ok = LightCDP.Page.fill(page, "#email", "user@example.com")
  """
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

  @doc """
  Fills form fields, submits the form, and waits for navigation.

  `fields` is a map of `%{selector => value}` pairs to fill before submitting.

  ## Options

    * `:timeout` - milliseconds (default: `30_000`)

  ## Example

      :ok = LightCDP.Page.submit(page, "#login-form", %{
        "#email" => "user@example.com",
        "#password" => "secret"
      })

      # Submit with no fields
      :ok = LightCDP.Page.submit(page, "form")
  """
  def submit(page, form_selector, fields \\ %{}, opts \\ []) do
    with :ok <- fill_fields(page, fields, opts) do
      wait_for_navigation(
        page,
        fn ->
          evaluate(page, """
          (() => {
            const form = document.querySelector(#{Jason.encode!(form_selector)});
            if (!form) throw new Error('Form not found: #{form_selector}');
            form.submit();
          })()
          """)
        end,
        opts
      )
    end
  end

  @doc """
  Polls the DOM until an element matching `selector` appears.

  Returns `:ok` when found, `{:error, :timeout}` if it doesn't appear
  within the timeout.

  ## Options

    * `:timeout` - milliseconds (default: `15_000`)
    * `:interval` - polling interval in milliseconds (default: `100`)

  ## Example

      :ok = LightCDP.Page.wait_for_selector(page, ".search-results", timeout: 5_000)
  """
  def wait_for_selector(page, selector, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout
    interval = opts[:interval] || 100
    deadline = System.monotonic_time(:millisecond) + timeout

    poll_selector(page, selector, interval, deadline)
  end

  defp poll_selector(page, selector, interval, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, LightCDP.TimeoutError.new(operation: :wait_for_selector)}
    else
      case query_selector(page, selector, 5_000) do
        {:ok, _node_id} ->
          :ok

        {:error, _} ->
          Process.sleep(interval)
          poll_selector(page, selector, interval, deadline)
      end
    end
  end

  @doc """
  Registers an event waiter, calls `fun`, then waits for a `Page.loadEventFired` event.

  If `fun` returns `{:error, _}`, short-circuits immediately without waiting.

  ## Options

    * `:timeout` - milliseconds (default: `30_000`)

  ## Example

      :ok = LightCDP.Page.wait_for_navigation(page, fn ->
        LightCDP.Page.click(page, "a.next-page")
      end)
  """
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
        {:error, LightCDP.ElementNotFoundError.new(selector)}
      else
        {:ok, node_id}
      end
    else
      {:error, %LightCDP.CDPError{}} ->
        {:error, LightCDP.ElementNotFoundError.new(selector)}

      other ->
        other
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
      send_cdp(
        conn,
        sid,
        "Input.dispatchMouseEvent",
        %{
          type: type,
          x: x,
          y: y,
          button: "left",
          clickCount: 1
        },
        timeout
      )
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
           send_cdp(
             conn,
             sid,
             "Runtime.callFunctionOn",
             %{
               objectId: object_id,
               functionDeclaration: "function() { this.focus(); }"
             },
             timeout
           ) do
      :ok
    end
  end

  defp clear_value(%{conn: conn, session_id: sid}, object_id, timeout) do
    with {:ok, _} <-
           send_cdp(
             conn,
             sid,
             "Runtime.callFunctionOn",
             %{
               objectId: object_id,
               functionDeclaration: "function() { this.value = ''; }"
             },
             timeout
           ) do
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
        {:error, LightCDP.JavaScriptError.new(desc)}

      %{"exceptionDetails" => details} ->
        {:error, LightCDP.JavaScriptError.new(inspect(details))}

      %{"result" => %{"value" => value}} ->
        {:ok, value}

      %{"result" => %{"type" => "undefined"}} ->
        {:ok, nil}

      %{"result" => inner} ->
        {:ok, inner["value"]}
    end
  end
end
