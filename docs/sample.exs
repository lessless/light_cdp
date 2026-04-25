# Hacker News search extraction script
# Elixir equivalent of https://lightpanda.io/docs/quickstart/build-your-first-extraction-script
#
# Usage: elixir docs/sample.exs
#
# Starts Lightpanda, navigates to Hacker News, searches for "lightpanda",
# waits for results, and extracts structured data (title, url, metadata).

Mix.install([
  {:light_cdp, path: Path.expand("..", __DIR__)},
  {:jason, "~> 1.4"}
])

{:ok, session} = LightCDP.start()
{:ok, page} = LightCDP.new_page(session)

# Navigate to Hacker News
IO.puts("Navigating to Hacker News...")
:ok = LightCDP.Page.navigate(page, "https://news.ycombinator.com/")

# Type "lightpanda" into the search field and submit
IO.puts("Searching for 'lightpanda'...")
:ok = LightCDP.Page.fill(page, "input[name=\"q\"]", "lightpanda")

:ok =
  LightCDP.Page.wait_for_navigation(page, fn ->
    LightCDP.Page.evaluate(page, "document.querySelector('input[name=\"q\"]').form.submit()")
  end)

# Wait for search results to load
IO.puts("Waiting for results...")
:ok = LightCDP.Page.wait_for_selector(page, ".Story_container", timeout: 5_000)

# Extract structured data from search results
IO.puts("Extracting results...\n")

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

# Print results
for result <- results do
  IO.puts(result["title"])
  IO.puts("  #{result["url"]}")
  IO.puts("  #{Enum.join(result["meta"], " · ")}")
  IO.puts("")
end

IO.puts("Found #{length(results)} results.")

LightCDP.stop(session)
