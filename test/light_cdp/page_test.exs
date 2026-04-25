defmodule LightCDP.PageTest do
  use ExUnit.Case

  setup_all do
    {:ok, server, endpoint} = LightCDP.Server.start(port: 9223)
    on_exit(fn -> LightCDP.Server.stop(server) end)
    %{endpoint: endpoint}
  end

  setup %{endpoint: endpoint} do
    {:ok, conn} = LightCDP.Connection.open(endpoint)
    {:ok, page} = LightCDP.Page.new(conn)
    on_exit(fn -> LightCDP.Connection.close(conn) end)
    %{page: page}
  end

  describe "navigate/2" do
    test "navigates to a URL", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")
      {:ok, title} = LightCDP.Page.evaluate(page, "document.title")
      assert title =~ "Example"
    end
  end

  describe "evaluate/2" do
    test "returns string results", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")
      {:ok, text} = LightCDP.Page.evaluate(page, "document.querySelector('h1').textContent")
      assert text == "Example Domain"
    end

    test "returns numeric results", %{page: page} do
      {:ok, result} = LightCDP.Page.evaluate(page, "1 + 2")
      assert result == 3
    end

    test "returns null for undefined", %{page: page} do
      {:ok, result} = LightCDP.Page.evaluate(page, "undefined")
      assert is_nil(result)
    end

    test "returns boolean results", %{page: page} do
      {:ok, result} = LightCDP.Page.evaluate(page, "true")
      assert result == true
    end
  end

  describe "url/1" do
    test "returns the current page URL", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")
      {:ok, url} = LightCDP.Page.url(page)
      assert url =~ "example.com"
    end

    test "returns about:blank for a new page", %{page: page} do
      {:ok, url} = LightCDP.Page.url(page)
      assert url == "about:blank"
    end
  end

  describe "content/1" do
    test "returns the page HTML", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")
      {:ok, html} = LightCDP.Page.content(page)
      assert html =~ "<h1>Example Domain</h1>"
      assert html =~ "<html"
    end
  end

  describe "click/2" do
    test "clicks an element by selector", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")

      :ok =
        LightCDP.Page.wait_for_navigation(page, fn ->
          LightCDP.Page.click(page, "a")
        end)

      {:ok, url} = LightCDP.Page.url(page)
      assert url != "https://example.com/"
    end
  end

  describe "fill/3" do
    test "fills an input field", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")

      # Inject an input into the page
      {:ok, _} =
        LightCDP.Page.evaluate(page, """
        document.body.innerHTML = '<input id="name" type="text">';
        """)

      :ok = LightCDP.Page.fill(page, "#name", "hello world")

      {:ok, value} = LightCDP.Page.evaluate(page, "document.querySelector('#name').value")
      assert value == "hello world"
    end
  end

  describe "submit/3" do
    test "fills fields and submits a form", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")

      {:ok, _} =
        LightCDP.Page.evaluate(page, """
        document.body.innerHTML = `
          <form action="https://example.com/submitted">
            <input id="user" type="text">
            <input id="pass" type="password">
          </form>
        `;
        """)

      :ok = LightCDP.Page.submit(page, "form", %{"#user" => "alice", "#pass" => "secret"})

      {:ok, url} = LightCDP.Page.url(page)
      assert url =~ "submitted"
    end

    test "submits with no fields to fill", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")

      {:ok, _} =
        LightCDP.Page.evaluate(page, """
        document.body.innerHTML = '<form action="https://example.com/done"></form>';
        """)

      :ok = LightCDP.Page.submit(page, "form")

      {:ok, url} = LightCDP.Page.url(page)
      assert url =~ "done"
    end

    test "returns error when form not found", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")
      assert {:error, _} = LightCDP.Page.submit(page, "#nonexistent")
    end
  end

  describe "error handling" do
    test "evaluate returns error for JS exceptions", %{page: page} do
      assert {:error, _} = LightCDP.Page.evaluate(page, "throw new Error('boom')")
    end

    test "click returns error for missing selector", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")
      assert {:error, _} = LightCDP.Page.click(page, "#nonexistent")
    end

    test "fill returns error for missing selector", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")
      assert {:error, _} = LightCDP.Page.fill(page, "#nonexistent", "value")
    end
  end

  describe "timeouts" do
    test "navigate returns {:error, :timeout} with impossible timeout", %{page: page} do
      result = LightCDP.Page.navigate(page, "https://example.com", timeout: 1)
      assert result == {:error, :timeout}
    end

    test "wait_for_navigation returns {:error, :timeout} when no navigation occurs", %{page: page} do
      result = LightCDP.Page.wait_for_navigation(page, fn -> :noop end, timeout: 100)
      assert result == {:error, :timeout}
    end

    test "evaluate accepts timeout option", %{page: page} do
      # Should succeed with generous timeout
      assert {:ok, 3} = LightCDP.Page.evaluate(page, "1 + 2", timeout: 5_000)
    end

    test "default timeouts work for normal operations", %{page: page} do
      assert :ok = LightCDP.Page.navigate(page, "https://example.com")
      assert {:ok, _} = LightCDP.Page.evaluate(page, "1 + 1")
    end
  end

  describe "wait_for_navigation/2" do
    test "waits for navigation after a JS-triggered redirect", %{page: page} do
      :ok = LightCDP.Page.navigate(page, "https://example.com")

      :ok =
        LightCDP.Page.wait_for_navigation(page, fn ->
          LightCDP.Page.evaluate(page, "document.querySelector('a').click()")
        end)

      {:ok, url} = LightCDP.Page.url(page)
      assert url != "https://example.com/"
    end
  end
end
