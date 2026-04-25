defmodule LightCDP.IntegrationTest do
  use ExUnit.Case, async: true

  test "full flow: start server, open page, navigate, evaluate, stop" do
    {:ok, session} = LightCDP.start(port: 9227)
    {:ok, page} = LightCDP.new_page(session)

    :ok = LightCDP.Page.navigate(page, "https://example.com")
    {:ok, title} = LightCDP.Page.evaluate(page, "document.title")
    assert title =~ "Example"

    {:ok, h1} = LightCDP.Page.evaluate(page, "document.querySelector('h1').textContent")
    assert h1 == "Example Domain"

    LightCDP.stop(session)
  end
end
