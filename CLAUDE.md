# Development

All changes to this codebase MUST follow TDD with the full red-green-refactor cycle:

1. **RED** — Write a failing test first. Run it. See it fail.
2. **GREEN** — Write the minimum code to make the test pass. Nothing more.
3. **REFACTOR** — Clean up while keeping tests green. Remove duplication, improve names, simplify.

Do not skip steps. Do not write implementation before a failing test exists.

## Design rules

Follow Beck's four rules of simple design (https://martinfowler.com/bliki/BeckDesignRules.html), in priority order:

1. **Passes the tests** — The code works.
2. **Reveals intention** — Names and structure make the code's purpose obvious.
3. **No duplication** — Every piece of knowledge has a single representation.
4. **Fewest elements** — No extra modules, functions, or abstractions beyond what the above rules require.

When in doubt, delete code rather than add it.

## Documentation

All public functions MUST have `@doc` with a description, options (if any), and at least one example. All public modules MUST have `@moduledoc`. When changing a function's behavior or return type, update its `@doc` in the same commit. Run `mix docs` to verify.

Before committing, check if `README.md` needs updating. The README describes responsibilities, not implementation details — update it when adding or removing modules, changing the public API surface, or altering how the library works at a high level. Do not list specific functions in the README.

## Running tests

```
mix test                           # all tests
mix test test/light_cdp/page_test.exs  # specific file
mix test --only describe:"click/2"     # specific describe block
```

Kill leftover Lightpanda processes before running tests:
```
pkill -f "lightpanda.*serve"
```

## Architecture

- `LightCDP` — top-level API (start/stop/new_page)
- `LightCDP.Connection` — WebSocket CDP client (WebSockex)
- `LightCDP.Page` — page interactions (navigate, evaluate, click, fill, submit, wait_for_selector, wait_for_navigation)
- `LightCDP.Protocol` — JSON encode/decode for CDP messages
- `LightCDP.Server` — Lightpanda process management (erlexec)

Page operations use native CDP methods (DOM.querySelector, DOM.getBoxModel, Input.dispatchMouseEvent, Input.insertText, DOM.getOuterHTML) where supported by Lightpanda, falling back to Runtime.evaluate for operations without a CDP equivalent (url, submit).

## Lightpanda binary

Resolved in order: `opts[:binary]` > `Application.get_env(:light_cdp, :lightpanda_path)` > `~/.local/bin/lightpanda`
