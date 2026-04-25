defmodule LightCDP.ConnectionTest do
  use ExUnit.Case, async: true

  setup_all do
    {:ok, server, endpoint} = LightCDP.Server.start(port: 9222)
    on_exit(fn -> LightCDP.Server.stop(server) end)
    %{endpoint: endpoint}
  end

  test "connects to a CDP endpoint", %{endpoint: endpoint} do
    {:ok, conn} = LightCDP.Connection.open(endpoint)
    assert is_pid(conn)
    LightCDP.Connection.close(conn)
  end

  test "sends a command and receives a response", %{endpoint: endpoint} do
    {:ok, conn} = LightCDP.Connection.open(endpoint)

    {:ok, result} = LightCDP.Connection.send_command(conn, "Browser.getVersion")
    assert result["product"] =~ "Chrome"
    assert result["protocolVersion"] == "1.3"

    LightCDP.Connection.close(conn)
  end

  test "creates a target", %{endpoint: endpoint} do
    {:ok, conn} = LightCDP.Connection.open(endpoint)

    {:ok, result} =
      LightCDP.Connection.send_command(conn, "Target.createTarget", %{url: "about:blank"})

    assert is_binary(result["targetId"])

    LightCDP.Connection.close(conn)
  end

  test "open returns ConnectionError for unreachable endpoint" do
    assert {:error, %LightCDP.ConnectionError{}} =
             LightCDP.Connection.open("http://127.0.0.1:19999")
  end
end
