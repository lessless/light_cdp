defmodule LightCDP do
  @moduledoc """
  A minimal CDP (Chrome DevTools Protocol) client for Elixir.

  Connects directly to [Lightpanda](https://lightpanda.io/) via WebSocket.
  No Node.js, Playwright, or Puppeteer required.

  ## Quick start

      {:ok, session} = LightCDP.start()
      {:ok, page} = LightCDP.new_page(session)

      :ok = LightCDP.Page.navigate(page, "https://example.com")
      {:ok, title} = LightCDP.Page.evaluate(page, "document.title")
      # => {:ok, "Example Domain"}

      LightCDP.stop(session)

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
