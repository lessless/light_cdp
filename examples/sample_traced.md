# Hacker News Search with OpenTelemetry

Same as the basic sample, but with traces exported to Jaeger.

## Prerequisites

```sh
# Start Jaeger
jaeger
# or: docker run -d -p 16686:16686 -p 4318:4318 jaegertracing/jaeger:latest
```

## Run

```sh
elixir examples/sample_traced.exs
# Then open http://localhost:16686 → service "light_cdp_sample"
```

## How it works

1. Configures the OTLP exporter to send to `localhost:4318`
2. Calls `LightCDP.Telemetry.OtelBridge.setup()` to bridge telemetry events to OTel spans
3. Wraps the workflow in `OpenTelemetry.Tracer.with_span` for a single root trace
4. All page operations and CDP commands appear as nested spans in Jaeger

```elixir
LightCDP.Telemetry.OtelBridge.setup()

OpenTelemetry.Tracer.with_span "hn_search" do
  {:ok, session} = LightCDP.start()
  {:ok, page} = LightCDP.new_page(session)

  LightCDP.Page.navigate(page, "https://news.ycombinator.com/")
  LightCDP.Page.fill(page, "input[name=\"q\"]", "lightpanda")
  # ...

  LightCDP.stop(session)
end
```

Multi-step operations like `fill` include span events showing internal steps (focus, clear, insert) — visible as logs within the span in Jaeger.

See [`sample_traced.exs`](https://github.com/lessless/light_cdp/blob/main/examples/sample_traced.exs) for the full runnable script.
