defmodule LightCDP do
  @moduledoc """
  A minimal CDP (Chrome DevTools Protocol) client for Elixir, built for
  [Lightpanda](https://lightpanda.io/).

  ## Why Lightpanda

  Headless Chrome carries the full rendering pipeline — CSS parsing, layout,
  compositing, painting — even when no human is looking at the result.
  [Lightpanda strips all of that away](https://lightpanda.io/blog/posts/what-is-a-true-headless-browser),
  keeping only the DOM and JavaScript engine, which cuts resource usage by
  60-80% for automation workloads.

  It's [written in Zig](https://lightpanda.io/blog/posts/why-we-built-lightpanda-in-zig)
  for explicit memory control via arena allocators — critical when crawling
  thousands of pages — with seamless C interop for embedding V8. The
  [custom DOM implementation](https://lightpanda.io/blog/posts/migrating-our-dom-to-zig)
  consolidates allocations and uses compile-time V8 snapshots to cut startup
  time by 10-30%.

  ## Why LightCDP

  Existing Elixir browser automation libraries (`playwright_ex`,
  `playwright-elixir`) route commands through a Node.js Playwright driver.
  LightCDP talks CDP over WebSocket directly to Lightpanda — no Node.js,
  no Playwright, no Puppeteer in the middle.

  ## Quick start

      {:ok, session} = LightCDP.start()
      {:ok, page} = LightCDP.new_page(session)

      :ok = LightCDP.Page.navigate(page, "https://example.com")
      {:ok, title} = LightCDP.Page.evaluate(page, "document.title")
      # => {:ok, "Example Domain"}

      LightCDP.stop(session)

  See `LightCDP.Page` for the full interaction API (click, fill, submit,
  wait_for_selector, wait_for_navigation).

  ## Error handling

  All functions return `{:ok, result}`, `:ok`, or `{:error, exception}`.
  See `LightCDP.ElementNotFoundError`, `LightCDP.TimeoutError`,
  `LightCDP.JavaScriptError`, `LightCDP.CDPError`, and
  `LightCDP.ConnectionError`.

  ## Lightpanda binary

  The binary path is resolved in order:

  1. `LightCDP.start(binary: "/path/to/lightpanda")`
  2. `Application.get_env(:light_cdp, :lightpanda_path)`
  3. `~/.local/bin/lightpanda`

  Install via `curl -fsSL https://pkg.lightpanda.io/install.sh | bash`.
  """

  defstruct [:server, :conn]

  @doc """
  Starts a Lightpanda instance and connects to it.

  Returns `{:ok, session}` where `session` is used with `new_page/1` and `stop/1`.

  ## Options

    * `:port` - CDP server port (default: `9222`)
    * `:host` - CDP server host (default: `"127.0.0.1"`)
    * `:binary` - path to the Lightpanda binary
    * `:timeout` - Lightpanda inactivity timeout in seconds (default: `30`)

  ## Example

      {:ok, session} = LightCDP.start(port: 9222)
  """
  def start(opts \\ []) do
    {:ok, server, endpoint} = LightCDP.Server.start(opts)
    {:ok, conn} = LightCDP.Connection.open(endpoint)
    {:ok, %__MODULE__{server: server, conn: conn}}
  end

  @doc """
  Creates a new browser page (CDP target) within the session.

  ## Example

      {:ok, page} = LightCDP.new_page(session)
      :ok = LightCDP.Page.navigate(page, "https://example.com")
  """
  def new_page(%__MODULE__{conn: conn}) do
    LightCDP.Page.new(conn)
  end

  @doc """
  Stops the session, closing the WebSocket connection and killing Lightpanda.
  """
  def stop(%__MODULE__{server: server, conn: conn}) do
    LightCDP.Connection.close(conn)
    LightCDP.Server.stop(server)
    :ok
  end
end
