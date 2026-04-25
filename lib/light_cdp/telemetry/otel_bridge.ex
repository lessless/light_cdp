defmodule LightCDP.Telemetry.OtelBridge do
  @moduledoc """
  Bridges LightCDP telemetry events to OpenTelemetry spans.

  Requires `opentelemetry` and `opentelemetry_api` in your dependencies.
  Does not depend on `opentelemetry_telemetry` — uses the Erlang OTel API
  directly to manage span context via a process dictionary token stack.

  ## Setup

  In an OTP application, add the OTel deps and configure the exporter:

      # mix.exs
      {:opentelemetry, "~> 1.4"},
      {:opentelemetry_api, "~> 1.3"},
      {:opentelemetry_exporter, "~> 1.7"}

      # config/runtime.exs
      config :opentelemetry_exporter, otlp_endpoint: "http://localhost:4318"

  Then call `setup/0` from your `Application.start/2` callback:

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          LightCDP.Telemetry.OtelBridge.setup()

          children = [...]
          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end

  In a script, call it after `Mix.install`:

      Mix.install([
        {:light_cdp, "~> 0.2"},
        {:opentelemetry, "~> 1.4"},
        {:opentelemetry_api, "~> 1.3"},
        {:opentelemetry_exporter, "~> 1.7"}
      ])
      LightCDP.Telemetry.OtelBridge.setup()

  All LightCDP page operations will then produce OTel spans. Wrap your
  workflow in a root span for a single trace:

      require OpenTelemetry.Tracer
      OpenTelemetry.Tracer.with_span "my_workflow" do
        {:ok, session} = LightCDP.start()
        {:ok, page} = LightCDP.new_page(session)
        LightCDP.Page.navigate(page, "https://example.com")
        LightCDP.stop(session)
      end

  ## Teardown

      LightCDP.Telemetry.OtelBridge.teardown()
  """

  @tracer_id :light_cdp
  @start_id "light-cdp-otel-start"
  @stop_id "light-cdp-otel-stop"
  @exception_id "light-cdp-otel-exception"
  @step_id "light-cdp-otel-step"

  @doc """
  Attaches telemetry handlers that create OpenTelemetry spans.
  """
  def setup do
    events = LightCDP.Telemetry.events()
    start_events = Enum.filter(events, &match?([_, _, _, :start], &1))
    stop_events = Enum.filter(events, &match?([_, _, _, :stop], &1))
    exception_events = Enum.filter(events, &match?([_, _, _, :exception], &1))

    :telemetry.attach_many(@start_id, start_events, &__MODULE__.handle_start/4, nil)
    :telemetry.attach_many(@stop_id, stop_events, &__MODULE__.handle_stop/4, nil)
    :telemetry.attach(@step_id, [:light_cdp, :page, :step], &__MODULE__.handle_step/4, nil)
    :telemetry.attach_many(@exception_id, exception_events, &__MODULE__.handle_exception/4, nil)
    :ok
  end

  @doc """
  Detaches the OpenTelemetry telemetry handlers.
  """
  def teardown do
    :telemetry.detach(@start_id)
    :telemetry.detach(@stop_id)
    :telemetry.detach(@exception_id)
    :telemetry.detach(@step_id)
    :ok
  end

  @doc """
  Computes the OTel span name from a telemetry event and metadata.

  Connection commands include the CDP method for at-a-glance readability:

      "connection.command DOM.querySelector"
      "connection.command Page.navigate"

  Page operations use `module.operation`:

      "page.navigate"
      "page.click"
  """
  def span_name([:light_cdp, :connection, :command, _suffix], %{method: method}) do
    "connection.command #{method}"
  end

  def span_name([:light_cdp, module, operation, _suffix], _metadata) do
    "#{module}.#{operation}"
  end

  @doc false
  def handle_start(event, _measurements, metadata, _) do
    name = span_name(event, metadata)
    attrs = to_attributes(metadata)

    tracer = :opentelemetry.get_tracer(@tracer_id)
    ctx = :otel_ctx.get_current()
    span_ctx = :otel_tracer.start_span(ctx, tracer, name, %{attributes: attrs})
    new_ctx = :otel_tracer.set_current_span(ctx, span_ctx)
    token = :otel_ctx.attach(new_ctx)

    stack = Process.get(:otel_token_stack, [])
    Process.put(:otel_token_stack, [token | stack])
  end

  @doc false
  def handle_stop(_event, %{duration: duration}, _metadata, _) do
    span_ctx = :otel_tracer.current_span_ctx()
    ms = System.convert_time_unit(duration, :native, :millisecond)
    :otel_span.set_attribute(span_ctx, :duration_ms, ms)
    :otel_span.end_span(span_ctx)
    pop_token()
  end

  @doc false
  def handle_step(_event, _measurements, %{step: step} = metadata, _) do
    span_ctx = :otel_tracer.current_span_ctx()
    attrs = metadata |> Map.delete(:step) |> to_attributes()
    :otel_span.add_event(span_ctx, to_string(step), attrs)
  end

  @doc false
  def handle_exception(_event, _measurements, metadata, _) do
    span_ctx = :otel_tracer.current_span_ctx()
    :otel_span.set_status(span_ctx, :error, inspect(metadata[:reason]))
    :otel_span.end_span(span_ctx)
    pop_token()
  end

  defp pop_token do
    case Process.get(:otel_token_stack, []) do
      [token | rest] ->
        :otel_ctx.detach(token)
        Process.put(:otel_token_stack, rest)

      [] ->
        :ok
    end
  end

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
