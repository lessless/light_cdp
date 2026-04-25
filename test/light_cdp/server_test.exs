defmodule LightCDP.ServerTest do
  use ExUnit.Case, async: true

  test "starts Lightpanda and returns endpoint" do
    {:ok, server, endpoint} = LightCDP.Server.start(port: 9224)
    assert endpoint == "http://127.0.0.1:9224"

    {:ok, resp} = Req.get(endpoint <> "/json/version", retry: false)
    assert resp.body["webSocketDebuggerUrl"]

    LightCDP.Server.stop(server)
  end

  test "accepts a custom binary path" do
    binary = Path.join([System.get_env("HOME"), ".local", "bin", "lightpanda"])
    {:ok, server, _endpoint} = LightCDP.Server.start(binary: binary, port: 9225)
    LightCDP.Server.stop(server)
  end

  test "uses application env for default path" do
    Application.put_env(:light_cdp, :lightpanda_path, Path.join([System.get_env("HOME"), ".local", "bin", "lightpanda"]))
    {:ok, server, _endpoint} = LightCDP.Server.start(port: 9226)
    LightCDP.Server.stop(server)
    Application.delete_env(:light_cdp, :lightpanda_path)
  end

  test "stop kills the OS process" do
    {:ok, server, endpoint} = LightCDP.Server.start(port: 9228)

    # Verify it's running
    assert {:ok, %{status: 200}} = Req.get(endpoint <> "/json/version", retry: false)

    LightCDP.Server.stop(server)
    Process.sleep(200)

    # Verify it's dead
    assert {:error, _} = Req.get(endpoint <> "/json/version", retry: false)
  end
end
