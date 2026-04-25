defmodule LightCDP.ProtocolTest do
  use ExUnit.Case

  describe "encode/3" do
    test "encodes a command with id, method, and params" do
      encoded = LightCDP.Protocol.encode(1, "Page.navigate", %{url: "https://example.com"})
      assert Jason.decode!(encoded) == %{"id" => 1, "method" => "Page.navigate", "params" => %{"url" => "https://example.com"}}
    end

    test "encodes a command with empty params by default" do
      encoded = LightCDP.Protocol.encode(2, "Page.enable")
      assert Jason.decode!(encoded) == %{"id" => 2, "method" => "Page.enable", "params" => %{}}
    end
  end

  describe "decode/1" do
    test "decodes a command response" do
      json = Jason.encode!(%{id: 1, result: %{frameId: "F1"}})
      assert LightCDP.Protocol.decode(json) == {:response, 1, %{"frameId" => "F1"}}
    end

    test "decodes an error response" do
      json = Jason.encode!(%{id: 1, error: %{code: -32601, message: "not found"}})

      assert LightCDP.Protocol.decode(json) ==
               {:error, 1, %{"code" => -32601, "message" => "not found"}}
    end

    test "decodes an event" do
      json = Jason.encode!(%{method: "Page.loadEventFired", params: %{timestamp: 123.4}})
      assert LightCDP.Protocol.decode(json) == {:event, "Page.loadEventFired", %{"timestamp" => 123.4}}
    end
  end
end
