defmodule LightCDP do
  @moduledoc """
  A minimal CDP (Chrome DevTools Protocol) client for Elixir.
  Connects directly to CDP endpoints like Lightpanda via WebSocket.
  No Node.js required.
  """

  defstruct [:server, :conn]

  def start(opts \\ []) do
    {:ok, server, endpoint} = LightCDP.Server.start(opts)
    {:ok, conn} = LightCDP.Connection.open(endpoint)
    {:ok, %__MODULE__{server: server, conn: conn}}
  end

  def new_page(%__MODULE__{conn: conn}) do
    LightCDP.Page.new(conn)
  end

  def stop(%__MODULE__{server: server, conn: conn}) do
    LightCDP.Connection.close(conn)
    LightCDP.Server.stop(server)
    :ok
  end
end
