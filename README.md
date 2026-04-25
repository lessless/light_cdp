# LightCDP

A minimal Elixir client for the [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/). Connects directly to [Lightpanda](https://lightpanda.io/) via WebSocket. No Node.js required.

## Quick example

```elixir
{:ok, session} = LightCDP.start()
{:ok, page} = LightCDP.new_page(session)

:ok = LightCDP.Page.navigate(page, "https://example.com")
{:ok, title} = LightCDP.Page.evaluate(page, "document.title")
# => {:ok, "Example Domain"}

LightCDP.stop(session)
```

See [`docs/sample.exs`](docs/sample.exs) for a full extraction script that searches Hacker News and returns structured results.

## Installation

Add `light_cdp` to your dependencies:

```elixir
def deps do
  [
    {:light_cdp, github: "lessless/light_cdp"}
  ]
end
```

Install the [Lightpanda](https://lightpanda.io/) binary:

```sh
curl -fsSL https://pkg.lightpanda.io/install.sh | bash
```

This places the binary at `~/.local/bin/lightpanda`, which is where LightCDP looks by default.

## API

### Lifecycle

```elixir
# Start Lightpanda and connect
{:ok, session} = LightCDP.start(port: 9222)

# Create a new page (CDP target)
{:ok, page} = LightCDP.new_page(session)

# ... use the page ...

# Stop everything
LightCDP.stop(session)
```

### Navigation

```elixir
:ok = LightCDP.Page.navigate(page, "https://example.com")

{:ok, url} = LightCDP.Page.url(page)
{:ok, html} = LightCDP.Page.content(page)
```

### Interacting with elements

```elixir
# Click an element (native CDP: querySelector -> getBoxModel -> dispatchMouseEvent)
:ok = LightCDP.Page.click(page, "#submit-btn")

# Fill an input (native CDP: resolveNode -> callFunctionOn(focus) -> insertText)
:ok = LightCDP.Page.fill(page, "#email", "user@example.com")

# Fill and submit a form in one call
:ok = LightCDP.Page.submit(page, "#login-form", %{
  "#email" => "user@example.com",
  "#password" => "secret"
})
```

### Evaluating JavaScript

```elixir
{:ok, result} = LightCDP.Page.evaluate(page, "document.title")
{:ok, count} = LightCDP.Page.evaluate(page, "document.querySelectorAll('a').length")
```

### Waiting

```elixir
# Wait for an element to appear in the DOM
:ok = LightCDP.Page.wait_for_selector(page, ".results", timeout: 5_000)

# Wait for a navigation triggered by a callback
:ok = LightCDP.Page.wait_for_navigation(page, fn ->
  LightCDP.Page.click(page, "a.next-page")
end)
```

### Error handling

All functions return `{:ok, result}` or `{:error, reason}`. Nothing crashes on failure.

```elixir
{:error, :timeout} = LightCDP.Page.navigate(page, "https://example.com", timeout: 1)
{:error, "Element not found: #nope"} = LightCDP.Page.click(page, "#nope")
{:error, _} = LightCDP.Page.evaluate(page, "throw new Error('boom')")
```

### Timeouts

All page operations accept a `timeout:` option in milliseconds. Defaults:

| Operation | Default |
|---|---|
| `navigate`, `wait_for_navigation`, `submit` | 30s |
| `evaluate`, `click`, `fill`, `wait_for_selector` | 15s |

## Lightpanda binary path

Resolved in order:

1. `LightCDP.start(binary: "/path/to/lightpanda")`
2. `Application.get_env(:light_cdp, :lightpanda_path)`
3. `~/.local/bin/lightpanda`

## How it works

LightCDP talks CDP over WebSocket directly to Lightpanda's built-in CDP server. No Playwright, no Puppeteer, no Node.js in the middle.

```
Elixir (LightCDP) --WebSocket--> Lightpanda (CDP server) --HTTP--> target site
```

Page interactions use native CDP methods where Lightpanda supports them:

| Function | CDP methods |
|---|---|
| `click` | `DOM.querySelector` -> `DOM.getBoxModel` -> `Input.dispatchMouseEvent` |
| `fill` | `DOM.resolveNode` -> `Runtime.callFunctionOn(focus/clear)` -> `Input.insertText` |
| `content` | `DOM.getDocument` -> `DOM.getOuterHTML` |
| `evaluate` | `Runtime.evaluate` |
| `navigate` | `Page.navigate` + `Page.loadEventFired` event |

## License

MIT
