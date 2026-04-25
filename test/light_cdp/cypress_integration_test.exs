defmodule LightCDP.CypressIntegrationTest do
  @moduledoc """
  Integration tests against https://example.cypress.io/
  Exercises every supported LightCDP feature against real-world HTML.
  """
  use ExUnit.Case, async: true

  @base "https://example.cypress.io"

  setup_all do
    {:ok, server, endpoint} = LightCDP.Server.start(port: 9230)
    on_exit(fn -> LightCDP.Server.stop(server) end)
    %{endpoint: endpoint}
  end

  setup %{endpoint: endpoint} do
    {:ok, conn} = LightCDP.Connection.open(endpoint)
    {:ok, page} = LightCDP.Page.new(conn)
    on_exit(fn -> LightCDP.Connection.close(conn) end)
    %{page: page}
  end

  # ------- navigate -------

  describe "navigate" do
    test "loads a page and updates URL", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base)
      {:ok, url} = LightCDP.Page.url(page)
      assert url =~ "example.cypress.io"
    end

    test "navigates between pages", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base <> "/commands/querying")
      {:ok, url1} = LightCDP.Page.url(page)
      assert url1 =~ "/commands/querying"

      :ok = LightCDP.Page.navigate(page, @base <> "/commands/actions")
      {:ok, url2} = LightCDP.Page.url(page)
      assert url2 =~ "/commands/actions"
    end
  end

  # ------- evaluate -------

  describe "evaluate" do
    test "reads page title", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base)
      {:ok, title} = LightCDP.Page.evaluate(page, "document.title")
      assert title =~ "Kitchen Sink"
    end

    test "queries DOM elements", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base <> "/commands/querying")
      {:ok, text} = LightCDP.Page.evaluate(page, "document.querySelector('#query-btn').textContent")
      assert text =~ "Button"
    end

    test "returns complex values", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base <> "/commands/querying")

      {:ok, count} =
        LightCDP.Page.evaluate(page, "document.querySelectorAll('.query-btn').length")

      assert is_number(count)
      assert count > 0
    end

    test "returns null for missing elements", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base)
      {:ok, result} = LightCDP.Page.evaluate(page, "document.querySelector('#nonexistent')")
      assert is_nil(result)
    end

    test "returns error for JS exceptions", %{page: page} do
      assert {:error, %LightCDP.JavaScriptError{}} =
               LightCDP.Page.evaluate(page, "throw new Error('test error')")
    end
  end

  # ------- content -------

  describe "content" do
    test "returns full page HTML", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base <> "/commands/querying")
      {:ok, html} = LightCDP.Page.content(page)
      assert html =~ "<html"
      assert html =~ "query-btn"
      assert html =~ "Querying"
    end
  end

  # ------- url -------

  describe "url" do
    test "returns current URL after navigation", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base <> "/commands/actions")
      {:ok, url} = LightCDP.Page.url(page)
      assert url == @base <> "/commands/actions"
    end

    test "returns about:blank for new page", %{page: page} do
      {:ok, url} = LightCDP.Page.url(page)
      assert url == "about:blank"
    end
  end

  # ------- click (native CDP) -------

  describe "click" do
    test "clicks a button by ID", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base <> "/commands/actions")

      # The .action-btn button exists on the page
      :ok = LightCDP.Page.click(page, ".action-btn")
    end

    test "clicks a link and navigates", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base)

      :ok =
        LightCDP.Page.wait_for_navigation(page, fn ->
          LightCDP.Page.click(page, "a[href='/commands/querying']")
        end)

      {:ok, url} = LightCDP.Page.url(page)
      assert url =~ "/commands/querying"
    end

    test "returns error for missing element", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base)

      assert {:error, %LightCDP.ElementNotFoundError{selector: "#nonexistent"}} =
               LightCDP.Page.click(page, "#nonexistent")
    end
  end

  # ------- fill (native CDP) -------

  describe "fill" do
    test "types into an email input", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base <> "/commands/actions")
      :ok = LightCDP.Page.fill(page, ".action-email", "test@example.com")

      {:ok, value} =
        LightCDP.Page.evaluate(page, "document.querySelector('.action-email').value")

      assert value == "test@example.com"
    end

    test "types into a password field", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base <> "/commands/actions")
      :ok = LightCDP.Page.fill(page, ".action-focus", "secretpass")

      {:ok, value} =
        LightCDP.Page.evaluate(page, "document.querySelector('.action-focus').value")

      assert value == "secretpass"
    end

    test "clears existing text before filling", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base <> "/commands/actions")

      # Fill twice — second should replace first
      :ok = LightCDP.Page.fill(page, ".action-email", "first@example.com")
      :ok = LightCDP.Page.fill(page, ".action-email", "second@example.com")

      {:ok, value} =
        LightCDP.Page.evaluate(page, "document.querySelector('.action-email').value")

      assert value == "second@example.com"
    end

    test "returns error for missing element", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base)

      assert {:error, %LightCDP.ElementNotFoundError{selector: "#nope"}} =
               LightCDP.Page.fill(page, "#nope", "text")
    end
  end

  # ------- submit -------

  describe "submit" do
    test "fills fields and submits a form that navigates", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base <> "/commands/actions")

      # Inject a form with a GET action that navigates
      {:ok, _} =
        LightCDP.Page.evaluate(page, """
        document.body.innerHTML = `
          <form action="#{@base}/commands/querying" method="get">
            <input id="code" type="text">
          </form>
        `;
        """)

      :ok = LightCDP.Page.submit(page, "form", %{"#code" => "HALFOFF"})

      {:ok, url} = LightCDP.Page.url(page)
      assert url =~ "/commands/querying"
    end

    test "submits with no fields", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base <> "/commands/actions")

      {:ok, _} =
        LightCDP.Page.evaluate(page, """
        document.body.innerHTML = '<form action="#{@base}/commands/querying" method="get"></form>';
        """)

      :ok = LightCDP.Page.submit(page, "form")

      {:ok, url} = LightCDP.Page.url(page)
      assert url =~ "/commands/querying"
    end

    test "returns error for missing form", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base)

      assert {:error, %LightCDP.JavaScriptError{}} =
               LightCDP.Page.submit(page, "#missing-form")
    end
  end

  # ------- wait_for_navigation -------

  describe "wait_for_navigation" do
    test "waits for click-triggered navigation", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base)

      :ok =
        LightCDP.Page.wait_for_navigation(page, fn ->
          LightCDP.Page.click(page, "a[href='/commands/actions']")
        end)

      {:ok, url} = LightCDP.Page.url(page)
      assert url =~ "/commands/actions"
    end

    test "waits for JS-triggered navigation", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base)

      :ok =
        LightCDP.Page.wait_for_navigation(page, fn ->
          LightCDP.Page.evaluate(page, "window.location.href = '#{@base}/commands/querying'")
        end)

      {:ok, url} = LightCDP.Page.url(page)
      assert url =~ "/commands/querying"
    end

    test "returns timeout when no navigation occurs", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base)

      assert {:error, %LightCDP.TimeoutError{}} =
               LightCDP.Page.wait_for_navigation(page, fn -> :noop end, timeout: 200)
    end

    test "short-circuits when callback errors", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base)

      result =
        LightCDP.Page.wait_for_navigation(page, fn ->
          {:error, "deliberate"}
        end)

      assert result == {:error, "deliberate"}
    end
  end

  # ------- timeouts -------

  describe "timeouts" do
    test "navigate times out with tiny timeout", %{page: page} do
      assert {:error, %LightCDP.TimeoutError{}} =
               LightCDP.Page.navigate(page, @base, timeout: 1)
    end

    test "evaluate works with explicit timeout", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base)
      assert {:ok, _} = LightCDP.Page.evaluate(page, "document.title", timeout: 5_000)
    end
  end

  # ------- full flow (multi-step) -------

  describe "multi-step flow" do
    test "navigates, fills fields, clicks through pages", %{page: page} do
      # Navigate to actions page
      :ok = LightCDP.Page.navigate(page, @base <> "/commands/actions")

      # Fill the email field using native CDP
      :ok = LightCDP.Page.fill(page, ".action-email", "user@test.com")
      {:ok, val} = LightCDP.Page.evaluate(page, "document.querySelector('.action-email').value")
      assert val == "user@test.com"

      # Read page content
      {:ok, html} = LightCDP.Page.content(page)
      assert html =~ "action-email"

      # Navigate home via click
      :ok =
        LightCDP.Page.wait_for_navigation(page, fn ->
          LightCDP.Page.click(page, ".navbar-brand")
        end)

      {:ok, url} = LightCDP.Page.url(page)
      assert url == @base <> "/"
    end

    test "navigates via clicks through multiple pages", %{page: page} do
      :ok = LightCDP.Page.navigate(page, @base)

      # Click to querying page
      :ok =
        LightCDP.Page.wait_for_navigation(page, fn ->
          LightCDP.Page.click(page, "a[href='/commands/querying']")
        end)

      {:ok, url} = LightCDP.Page.url(page)
      assert url =~ "/commands/querying"

      # Verify page content loaded
      {:ok, html} = LightCDP.Page.content(page)
      assert html =~ "query-btn"
    end
  end

  # ------- top-level API -------

  describe "LightCDP top-level API" do
    test "start/new_page/stop lifecycle" do
      {:ok, session} = LightCDP.start(port: 9231)
      {:ok, page} = LightCDP.new_page(session)

      :ok = LightCDP.Page.navigate(page, @base)
      {:ok, title} = LightCDP.Page.evaluate(page, "document.title")
      assert title =~ "Kitchen Sink"

      :ok = LightCDP.stop(session)
    end
  end
end
