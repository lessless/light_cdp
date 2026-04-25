# Hacker News search with OpenTelemetry tracing
#
# Prerequisites:
#   Jaeger running locally: jaeger (or docker run -d -p 16686:16686 -p 4318:4318 jaegertracing/jaeger:latest)
#
# Usage:
#   elixir docs/sample_traced.exs
#
# Then open http://localhost:16686 and look for service "light_cdp_sample"

# Start inets before Mix.install so the OTLP HTTP exporter can initialize cleanly
Application.ensure_all_started(:inets)
Application.ensure_all_started(:ssl)

# Configure OTel BEFORE Mix.install starts the applications
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
  {:opentelemetry_exporter, "~> 1.7"}
])

# --- Bridge LightCDP telemetry events to OpenTelemetry spans ---

defmodule LightCDP.OtelBridge do
  @tracer_id :light_cdp

  def setup do
    events = LightCDP.Telemetry.events()
    start_events = Enum.filter(events, &match?([_, _, _, :start], &1))
    stop_events = Enum.filter(events, &match?([_, _, _, :stop], &1))
    exception_events = Enum.filter(events, &match?([_, _, _, :exception], &1))

    :telemetry.attach_many("otel-start", start_events, &__MODULE__.handle_start/4, nil)
    :telemetry.attach_many("otel-stop", stop_events, &__MODULE__.handle_stop/4, nil)
    :telemetry.attach_many("otel-exception", exception_events, &__MODULE__.handle_exception/4, nil)
  end

  def handle_start(event, _measurements, metadata, _) do
    span_name = span_name(event)
    attrs = to_attributes(metadata)

    tracer = :opentelemetry.get_tracer(@tracer_id)
    ctx = :otel_ctx.get_current()
    span_ctx = :otel_tracer.start_span(ctx, tracer, span_name, %{attributes: attrs})
    new_ctx = :otel_tracer.set_current_span(ctx, span_ctx)
    token = :otel_ctx.attach(new_ctx)

    # Push token onto a stack so nested spans (page > connection) restore correctly
    stack = Process.get(:otel_token_stack, [])
    Process.put(:otel_token_stack, [token | stack])
  end

  def handle_stop(_event, %{duration: duration}, _metadata, _) do
    span_ctx = :otel_tracer.current_span_ctx()
    ms = System.convert_time_unit(duration, :native, :millisecond)
    :otel_span.set_attribute(span_ctx, :duration_ms, ms)
    :otel_span.end_span(span_ctx)

    case Process.get(:otel_token_stack, []) do
      [token | rest] ->
        :otel_ctx.detach(token)
        Process.put(:otel_token_stack, rest)

      [] ->
        :ok
    end
  end

  def handle_exception(_event, _measurements, metadata, _) do
    span_ctx = :otel_tracer.current_span_ctx()
    :otel_span.set_status(span_ctx, :error, inspect(metadata[:reason]))
    :otel_span.end_span(span_ctx)

    case Process.get(:otel_token_stack, []) do
      [token | rest] ->
        :otel_ctx.detach(token)
        Process.put(:otel_token_stack, rest)

      [] ->
        :ok
    end
  end

  defp span_name([_, module, operation, _suffix]), do: "#{module}.#{operation}"

  defp to_attributes(metadata) do
    metadata
    |> Map.drop([:session_id])
    |> Enum.flat_map(fn
      {k, v} when is_binary(v) -> [{k, v}]
      {k, v} when is_integer(v) -> [{k, v}]
      {k, v} when is_float(v) -> [{k, v}]
      {k, v} when is_atom(v) -> [{k, to_string(v)}]
      _ -> []
    end)
  end
end

LightCDP.OtelBridge.setup()
IO.puts("OpenTelemetry configured — traces will export to http://localhost:4318\n")

# --- Same script as sample.exs, wrapped in a root span ---

{:ok, session} = LightCDP.start()
{:ok, page} = LightCDP.new_page(session)

# Start a root span so all page operations nest under one trace
tracer = :opentelemetry.get_tracer(:light_cdp_sample)
root_ctx = :otel_ctx.get_current()
root_span = :otel_tracer.start_span(root_ctx, tracer, "hn_search", %{attributes: [{:query, "lightpanda"}]})
root_ctx = :otel_tracer.set_current_span(root_ctx, root_span)
_token = :otel_ctx.attach(root_ctx)

try do
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
after
  :otel_span.end_span(root_span)
end

LightCDP.stop(session)

# Flush spans to Jaeger before exit
try do
  :otel_tracer_provider.force_flush()
catch
  _, _ -> :ok
end

Process.sleep(2_000)
IO.puts("Traces exported. Open http://localhost:16686 → service 'light_cdp_sample'")
