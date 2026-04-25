# Hacker News Search

Navigates to Hacker News, searches for "lightpanda", waits for results, and extracts structured data.

```sh
elixir examples/sample.exs
```

## Source

```elixir
{:ok, session} = LightCDP.start()
{:ok, page} = LightCDP.new_page(session)

:ok = LightCDP.Page.navigate(page, "https://news.ycombinator.com/")
:ok = LightCDP.Page.fill(page, "input[name=\"q\"]", "lightpanda")

:ok =
  LightCDP.Page.wait_for_navigation(page, fn ->
    LightCDP.Page.evaluate(page, "document.querySelector('input[name=\"q\"]').form.submit()")
  end)

:ok = LightCDP.Page.wait_for_selector(page, ".Story_container", timeout: 5_000)

{:ok, results} =
  LightCDP.Page.evaluate(page, """
  Array.from(document.querySelectorAll('.Story_container')).map(row => ({
    title: row.querySelector('.Story_title span')?.textContent || '',
    url: row.querySelector('.Story_title a')?.getAttribute('href') || '',
    meta: Array.from(
      row.querySelectorAll('.Story_meta > span:not(.Story_separator, .Story_comment)')
    ).map(el => el.textContent)
  }));
  """)

LightCDP.stop(session)
```

See [`sample.exs`](https://github.com/lessless/light_cdp/blob/main/examples/sample.exs) for the full runnable script.
