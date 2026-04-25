# Changelog

## [v0.2.0](https://github.com/lessless/light_cdp/compare/v0.1.0...v0.2.0) (2026-04-25)

### Features

- Add `Page.screenshot/2` — native `Page.captureScreenshot`, returns decoded PNG binary
- Add `LightCDP.Telemetry` — telemetry spans (`:start`, `:stop`, `:exception`) for all page operations and CDP commands via `:telemetry.span/3`
- Add `LightCDP.Telemetry.OtelBridge` — optional OpenTelemetry span bridge with CDP method names in span names (e.g. `connection.command DOM.querySelector`)
- Add `attach_default_logger/1` — opt-in Logger output with step annotations for dev-time visibility
- Add step events (`[:light_cdp, :page, :step]`) for multi-step operations — fill emits focus/clear/insert, click emits query/locate/press/release

### Fixes

- `Connection.close/1` unlinks before exiting, preventing WebSocket close errors from propagating to the caller
- `attach_default_logger/1` is now idempotent (safe to call multiple times)

### Improvements

- Add `opentelemetry` and `opentelemetry_api` as optional dependencies (suppresses compile warnings for `OtelBridge`)
- Per-environment config — dev/test use `:none` exporter, prod is left to the consumer
- Rename `docs/` to `examples/` following Elixir conventions
- Add markdown guides as ex_doc extras
- Add tidewave MCP for dev tooling

## [v0.1.0](https://github.com/lessless/light_cdp/releases/tag/v0.1.0) (2026-04-25)

Initial release.

- CDP connection via WebSocket (no Node.js)
- Page operations: navigate, evaluate, click, fill, submit, content, url, wait_for_selector, wait_for_navigation
- Native CDP methods: DOM.querySelector, DOM.getBoxModel, Input.dispatchMouseEvent, Input.insertText, DOM.getOuterHTML
- Domain exceptions: ElementNotFoundError, TimeoutError, JavaScriptError, CDPError, ConnectionError
- Lightpanda process management via erlexec
- 75 tests including Cypress Kitchen Sink integration tests
