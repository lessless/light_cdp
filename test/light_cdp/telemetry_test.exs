defmodule LightCDP.TelemetryTest do
  use ExUnit.Case, async: true

  setup_all do
    {:ok, server, endpoint} = LightCDP.Server.start(port: 9240)
    on_exit(fn -> LightCDP.Server.stop(server) end)
    %{endpoint: endpoint}
  end

  setup %{endpoint: endpoint} do
    {:ok, conn} = LightCDP.Connection.open(endpoint)
    {:ok, page} = LightCDP.Page.new(conn)
    on_exit(fn -> LightCDP.Connection.close(conn) end)
    %{conn: conn, page: page}
  end

  defp attach_telemetry(events) do
    pid = self()
    id = "test-#{inspect(pid)}-#{System.unique_integer()}"

    :telemetry.attach_many(id, events, &__MODULE__.handle_telemetry_event/4, pid)

    on_exit(fn -> :telemetry.detach(id) end)
  end

  @doc false
  def handle_telemetry_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry, event, measurements, metadata})
  end

  describe "connection command telemetry" do
    test "emits start and stop for send_command", %{conn: conn} do
      attach_telemetry([
        [:light_cdp, :connection, :command, :start],
        [:light_cdp, :connection, :command, :stop]
      ])

      {:ok, _} = LightCDP.Connection.send_command(conn, "Browser.getVersion")

      assert_receive {:telemetry, [:light_cdp, :connection, :command, :start],
                      %{system_time: _}, %{method: "Browser.getVersion"}}

      assert_receive {:telemetry, [:light_cdp, :connection, :command, :stop],
                      %{duration: _}, %{method: "Browser.getVersion"}}
    end
  end

  describe "page telemetry" do
    test "navigate emits start and stop", %{page: page} do
      attach_telemetry([
        [:light_cdp, :page, :navigate, :start],
        [:light_cdp, :page, :navigate, :stop]
      ])

      :ok = LightCDP.Page.navigate(page, "https://example.com")

      assert_receive {:telemetry, [:light_cdp, :page, :navigate, :start],
                      %{system_time: _}, %{url: "https://example.com"}}

      assert_receive {:telemetry, [:light_cdp, :page, :navigate, :stop],
                      %{duration: _}, %{url: "https://example.com"}}
    end

    test "evaluate emits start and stop", %{page: page} do
      attach_telemetry([
        [:light_cdp, :page, :evaluate, :start],
        [:light_cdp, :page, :evaluate, :stop]
      ])

      {:ok, 3} = LightCDP.Page.evaluate(page, "1 + 2")

      assert_receive {:telemetry, [:light_cdp, :page, :evaluate, :start],
                      _, %{expression: "1 + 2"}}

      assert_receive {:telemetry, [:light_cdp, :page, :evaluate, :stop],
                      %{duration: _}, _}
    end

    test "click emits start and stop", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")

      attach_telemetry([
        [:light_cdp, :page, :click, :start],
        [:light_cdp, :page, :click, :stop]
      ])

      LightCDP.Page.click(page, "h1")

      assert_receive {:telemetry, [:light_cdp, :page, :click, :start],
                      _, %{selector: "h1"}}

      assert_receive {:telemetry, [:light_cdp, :page, :click, :stop],
                      %{duration: _}, _}
    end

    test "fill emits start and stop without value", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")

      {:ok, _} =
        LightCDP.Page.evaluate(page, "document.body.innerHTML = '<input id=\"x\">'")

      attach_telemetry([
        [:light_cdp, :page, :fill, :start],
        [:light_cdp, :page, :fill, :stop]
      ])

      :ok = LightCDP.Page.fill(page, "#x", "secret")

      assert_receive {:telemetry, [:light_cdp, :page, :fill, :start],
                      _, metadata}

      assert metadata.selector == "#x"
      refute Map.has_key?(metadata, :value)

      assert_receive {:telemetry, [:light_cdp, :page, :fill, :stop],
                      %{duration: _}, _}
    end

    test "screenshot emits start and stop", %{page: page} do
      attach_telemetry([
        [:light_cdp, :page, :screenshot, :start],
        [:light_cdp, :page, :screenshot, :stop]
      ])

      {:ok, _png} = LightCDP.Page.screenshot(page)

      assert_receive {:telemetry, [:light_cdp, :page, :screenshot, :start], _, _}
      assert_receive {:telemetry, [:light_cdp, :page, :screenshot, :stop], %{duration: _}, _}
    end

    test "content emits start and stop", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")

      attach_telemetry([
        [:light_cdp, :page, :content, :start],
        [:light_cdp, :page, :content, :stop]
      ])

      {:ok, _html} = LightCDP.Page.content(page)

      assert_receive {:telemetry, [:light_cdp, :page, :content, :start], _, _}
      assert_receive {:telemetry, [:light_cdp, :page, :content, :stop], %{duration: _}, _}
    end

    test "url emits start and stop", %{page: page} do
      attach_telemetry([
        [:light_cdp, :page, :url, :start],
        [:light_cdp, :page, :url, :stop]
      ])

      {:ok, _} = LightCDP.Page.url(page)

      assert_receive {:telemetry, [:light_cdp, :page, :url, :start], _, _}
      assert_receive {:telemetry, [:light_cdp, :page, :url, :stop], %{duration: _}, _}
    end

    test "wait_for_selector emits start and stop", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")

      attach_telemetry([
        [:light_cdp, :page, :wait_for_selector, :start],
        [:light_cdp, :page, :wait_for_selector, :stop]
      ])

      :ok = LightCDP.Page.wait_for_selector(page, "h1")

      assert_receive {:telemetry, [:light_cdp, :page, :wait_for_selector, :start],
                      _, %{selector: "h1"}}

      assert_receive {:telemetry, [:light_cdp, :page, :wait_for_selector, :stop],
                      %{duration: _}, _}
    end
  end

  describe "LightCDP.Telemetry" do
    test "events/0 returns all event names" do
      events = LightCDP.Telemetry.events()
      assert [:light_cdp, :page, :navigate, :start] in events
      assert [:light_cdp, :page, :navigate, :stop] in events
      assert [:light_cdp, :page, :navigate, :exception] in events
      assert [:light_cdp, :page, :click, :start] in events
      assert [:light_cdp, :connection, :command, :start] in events
      assert [:light_cdp, :connection, :command, :stop] in events
    end

    test "attach_default_logger/1 installs and detach removes handlers" do
      :ok = LightCDP.Telemetry.attach_default_logger()
      handlers = :telemetry.list_handlers([:light_cdp, :page, :navigate])
      assert length(handlers) > 0

      :ok = LightCDP.Telemetry.detach_default_logger()
      handlers = :telemetry.list_handlers([:light_cdp, :page, :navigate])
      assert Enum.empty?(handlers)
    end
  end
end
