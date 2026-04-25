# Observability

LightCDP emits telemetry events for all page operations and CDP commands. By default, nothing listens — zero overhead. Opt in per environment.

## Option 1: Logger (no extra deps)

Add one line to your `Application.start/2`:

```elixir
LightCDP.Telemetry.attach_default_logger(level: :debug)
```

Output:

```
[debug] navigate https://example.com
[debug] CDP Page.navigate
[debug] CDP Page.navigate in 657.2ms
[debug] navigate completed in 822.3ms
[debug] fill #email
[debug]   · focus
[debug]   · clear
[debug]   · insert (value_length=16)
[debug] fill completed in 3.1ms
```

Good for dev. No waterfall, no span nesting, but immediate visibility.

## Option 2: OpenTelemetry + Jaeger

Full distributed tracing with nested spans and a visual waterfall.

### Dependencies

```elixir
# mix.exs
{:opentelemetry, "~> 1.4"},
{:opentelemetry_api, "~> 1.3"},
{:opentelemetry_exporter, "~> 1.7"}
```

### Configuration

```elixir
# config/runtime.exs
config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: "http://localhost:4318"
```

### Setup

```elixir
# In Application.start/2
LightCDP.Telemetry.OtelBridge.setup()
```

### Root span

Wrap your workflow in a root span so all operations appear as one trace:

```elixir
require OpenTelemetry.Tracer

OpenTelemetry.Tracer.with_span "my_scraper" do
  {:ok, session} = LightCDP.start()
  {:ok, page} = LightCDP.new_page(session)
  LightCDP.Page.navigate(page, "https://example.com")
  # ...
  LightCDP.stop(session)
end
```

### What you see in Jaeger

```
my_scraper (1.8s)
├── connection.command Target.createTarget (30ms)
├── connection.command Target.attachToTarget (0.4ms)
├── connection.command Page.enable (0.4ms)
├── connection.command DOM.enable (0.2ms)
├── page.navigate (833ms)
│   └── connection.command Page.navigate (651ms)
├── page.fill (5ms)
│   ├── connection.command DOM.getDocument (1ms)
│   ├── connection.command DOM.querySelector (1ms)
│   ├── connection.command DOM.resolveNode (1ms)
│   ├── connection.command Runtime.callFunctionOn (1ms)  ← focus
│   ├── connection.command Runtime.callFunctionOn (1ms)  ← clear
│   └── connection.command Input.insertText (0.1ms)
├── page.wait_for_navigation (708ms)
│   └── page.evaluate → connection.command Runtime.evaluate
└── page.evaluate (1ms)
    └── connection.command Runtime.evaluate
```

Multi-step operations (`fill`, `click`) include span events visible as logs within the parent span — showing which step (focus, clear, insert) each CDP command belongs to.

### Running Jaeger locally

```sh
# Native binary
jaeger

# Or Docker
docker run -d -p 16686:16686 -p 4318:4318 jaegertracing/jaeger:latest
```

UI at [http://localhost:16686](http://localhost:16686).

## Telemetry events reference

See `LightCDP.Telemetry` for the full list of event names, metadata per operation, and the distinction between span events and step annotations.

For a runnable example, see [`examples/sample_traced.exs`](https://github.com/lessless/light_cdp/blob/main/examples/sample_traced.exs).
