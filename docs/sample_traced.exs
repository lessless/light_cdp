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

LightCDP.Telemetry.OtelBridge.setup()
IO.puts("OpenTelemetry configured — traces will export to http://localhost:4318\n")

# --- Same script as sample.exs, wrapped in a root span ---

defmodule HNSearch do
  require OpenTelemetry.Tracer

  def run do
    OpenTelemetry.Tracer.with_span "hn_search", %{attributes: [query: "lightpanda"]} do
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
    end
  end
end

HNSearch.run()

# Flush spans to Jaeger before exit
try do
  :otel_tracer_provider.force_flush()
catch
  _, _ -> :ok
end

Process.sleep(2_000)
IO.puts("Traces exported. Open http://localhost:16686 → service 'light_cdp_sample'")
