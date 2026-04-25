# Hacker News search with OpenTelemetry tracing
#
# Prerequisites:
#   Jaeger running locally (e.g. docker run -d --name jaeger -p 16686:16686 -p 4318:4318 jaegertracing/jaeger:latest)
#
# Usage:
#   elixir docs/sample_traced.exs
#
# Then open http://localhost:16686 and look for service "light_cdp_sample"

# Start inets before Mix.install so the OTLP HTTP exporter can initialize cleanly
Application.ensure_all_started(:inets)

Application.put_env(:opentelemetry, :resource, %{
  service: %{name: "light_cdp_sample"}
})

Application.put_env(:opentelemetry_exporter, :otlp_protocol, :http_protobuf)
Application.put_env(:opentelemetry_exporter, :otlp_endpoint, "http://localhost:4318")

Mix.install([
  {:light_cdp, path: Path.expand("..", __DIR__)},
  {:jason, "~> 1.4"},
  {:opentelemetry, "~> 1.4"},
  {:opentelemetry_api, "~> 1.3"},
  {:opentelemetry_exporter, "~> 1.7"},
  {:opentelemetry_telemetry, "~> 1.1"}
])

# --- Bridge LightCDP telemetry to OpenTelemetry spans ---

defmodule LightCDP.OtelBridge do
  require OpenTelemetry.Tracer

  @tracer_id __MODULE__

  def setup do
    events = LightCDP.Telemetry.events()
    start_events = Enum.filter(events, &match?([_, _, _, :start], &1))
    stop_events = Enum.filter(events, &match?([_, _, _, :stop], &1))
    exception_events = Enum.filter(events, &match?([_, _, _, :exception], &1))

    :telemetry.attach_many("otel-light-cdp-start", start_events, &handle_start/4, nil)
    :telemetry.attach_many("otel-light-cdp-stop", stop_events, &handle_stop/4, nil)
    :telemetry.attach_many("otel-light-cdp-exception", exception_events, &handle_exception/4, nil)
  end

  def handle_start([_, module, operation, :start], %{system_time: start_time}, metadata, _) do
    span_name = "#{module}.#{operation}"

    attributes =
      metadata
      |> Map.drop([:session_id])
      |> Enum.flat_map(fn
        {k, v} when is_binary(v) -> [{k, v}]
        {k, v} when is_number(v) -> [{k, v}]
        {k, v} when is_atom(v) -> [{k, to_string(v)}]
        _ -> []
      end)

    OpentelemetryTelemetry.start_telemetry_span(
      @tracer_id,
      span_name,
      metadata,
      %{start_time: start_time, attributes: attributes}
    )
  end

  def handle_stop([_, _module, _operation, :stop], %{duration: duration}, metadata, _) do
    OpentelemetryTelemetry.set_current_telemetry_span(@tracer_id, metadata)

    duration_ms = System.convert_time_unit(duration, :native, :millisecond)
    OpenTelemetry.Tracer.set_attribute(:duration_ms, duration_ms)

    OpentelemetryTelemetry.end_telemetry_span(@tracer_id, metadata)
  end

  def handle_exception([_, _module, _operation, :exception], _measurements, metadata, _) do
    OpentelemetryTelemetry.set_current_telemetry_span(@tracer_id, metadata)

    ctx = OpenTelemetry.Tracer.current_span_ctx()

    OpenTelemetry.Span.set_status(ctx, OpenTelemetry.status(:error, inspect(metadata[:reason])))

    OpentelemetryTelemetry.end_telemetry_span(@tracer_id, metadata)
  end
end

LightCDP.OtelBridge.setup()
IO.puts("OpenTelemetry configured — exporting to http://localhost:4318\n")

# --- Same script as sample.exs ---

{:ok, session} = LightCDP.start()
{:ok, page} = LightCDP.new_page(session)

IO.puts("Navigating to Hacker News...")
:ok = LightCDP.Page.navigate(page, "https://news.ycombinator.com/")

IO.puts("Searching for 'lightpanda'...")
:ok = LightCDP.Page.fill(page, "input[name=\"q\"]", "lightpanda")

:ok =
  LightCDP.Page.wait_for_navigation(page, fn ->
    LightCDP.Page.evaluate(page, "document.querySelector('input[name=\"q\"]').form.submit()")
  end)

IO.puts("Waiting for results...")
:ok = LightCDP.Page.wait_for_selector(page, ".Story_container", timeout: 5_000)

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

for result <- results do
  IO.puts(result["title"])
  IO.puts("  #{result["url"]}")
  IO.puts("  #{Enum.join(result["meta"], " · ")}")
  IO.puts("")
end

IO.puts("Found #{length(results)} results.")

LightCDP.stop(session)

# Flush spans before exit
try do
  :otel_tracer_provider.force_flush()
catch
  _, _ -> :ok
end

Process.sleep(1_000)
IO.puts("\nTraces exported. Open http://localhost:16686 → service 'light_cdp_sample'")
