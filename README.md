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

## Documentation

API docs are in the source modules — generate locally with `mix docs`, or read the `@doc` attributes directly:

- `LightCDP` — start/stop sessions, create pages
- `LightCDP.Page` — page interactions and DOM manipulation
- `LightCDP.Connection` — low-level WebSocket CDP client
- `LightCDP.Server` — Lightpanda process management
- `LightCDP.Protocol` — CDP message encoding/decoding
- `LightCDP.Telemetry` — telemetry event definitions and default logger

## How it works

LightCDP talks CDP over WebSocket directly to Lightpanda's built-in CDP server.

```
Elixir (LightCDP) --WebSocket--> Lightpanda (CDP server) --HTTP--> target site
```

Page interactions use native CDP methods where Lightpanda supports them (`DOM.querySelector`, `DOM.getBoxModel`, `Input.dispatchMouseEvent`, `Input.insertText`, `DOM.getOuterHTML`), falling back to `Runtime.evaluate` for operations without a CDP equivalent.

## License

MIT
