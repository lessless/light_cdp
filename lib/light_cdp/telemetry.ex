defmodule LightCDP.Telemetry do
  @moduledoc """
  Telemetry events emitted by LightCDP.

  All page operations and CDP commands emit `:start`, `:stop`, and
  `:exception` events via `:telemetry.span/3`.

  ## Page events

  Prefix: `[:light_cdp, :page, <operation>]`

  Operations: `navigate`, `evaluate`, `click`, `fill`, `submit`,
  `screenshot`, `content`, `url`, `wait_for_selector`, `wait_for_navigation`

  Measurements:
    * `:start` — `%{system_time: integer}`
    * `:stop` — `%{duration: native_time}`

  Metadata varies by operation (see `LightCDP.Page` function docs).

  ## Connection events

  Prefix: `[:light_cdp, :connection, :command]`

  Metadata: `%{method: String.t(), session_id: String.t() | nil}`

  ## Step events

  Multi-step operations (`fill`, `click`) emit point events at
  `[:light_cdp, :page, :step]` with `%{step: atom}` metadata.
  These are not spans — they annotate the parent span with what
  happened inside (focus, clear, insert, query, locate, etc.).

  ## Observability options

  By default, no handlers are attached (null sink). Opt in per environment:

      # Logger output (no extra deps, good for dev)
      LightCDP.Telemetry.attach_default_logger(level: :debug)

      # OpenTelemetry spans (requires :opentelemetry in deps, good for staging/prod)
      LightCDP.Telemetry.OtelBridge.setup()

  Call either from your `Application.start/2` callback or at script startup.
  """

  require Logger

  @handler_id "light-cdp-default-logger"

  @page_operations ~w(navigate evaluate click fill submit screenshot content url wait_for_selector wait_for_navigation)a

  @doc """
  Returns all span event names (`:start`, `:stop`, `:exception`) emitted by LightCDP.
  """
  def span_events do
    page_events =
      for op <- @page_operations, suffix <- [:start, :stop, :exception] do
        [:light_cdp, :page, op, suffix]
      end

    command_events =
      for suffix <- [:start, :stop, :exception] do
        [:light_cdp, :connection, :command, suffix]
      end

    page_events ++ command_events
  end

  @doc """
  Returns all telemetry event names emitted by LightCDP,
  including both span events and point events (step annotations).
  """
  def events do
    span_events() ++ [[:light_cdp, :page, :step]]
  end

  @doc """
  Attaches a default Logger handler for all LightCDP telemetry events,
  including step annotations for multi-step operations.

  Idempotent — safe to call multiple times.

  ## Options

    * `:level` - log level (default: `:debug`)

  ## Example output

      [debug] navigate https://example.com
      [debug] CDP Page.navigate
      [debug] CDP Page.navigate in 657.2ms
      [debug] navigate completed in 822.3ms
      [debug] fill #email
      [debug]   · focus
      [debug]   · clear
      [debug]   · insert (value_length=16)
      [debug] fill completed in 3.1ms
  """
  def attach_default_logger(opts \\ []) do
    detach_default_logger()
    level = opts[:level] || :debug

    :telemetry.attach_many(
      @handler_id,
      events(),
      &__MODULE__.handle_event/4,
      %{level: level}
    )
  end

  @doc """
  Detaches the default Logger handler.
  """
  def detach_default_logger do
    :telemetry.detach(@handler_id)
  catch
    _, _ -> :ok
  end

  @doc false
  def handle_event(event, measurements, metadata, %{level: level}) do
    Logger.log(level, fn -> format_event(event, measurements, metadata) end)
  end

  defp format_event([:light_cdp, :page, op, :start], _measurements, metadata) do
    "#{op} #{format_detail(op, metadata)}"
  end

  defp format_event([:light_cdp, :page, op, :stop], %{duration: duration}, _metadata) do
    "#{op} completed in #{format_duration(duration)}"
  end

  defp format_event([:light_cdp, :page, op, :exception], _measurements, %{kind: kind, reason: reason}) do
    "#{op} raised #{kind}: #{inspect(reason)}"
  end

  defp format_event([:light_cdp, :connection, :command, :start], _measurements, %{method: method}) do
    "CDP #{method}"
  end

  defp format_event([:light_cdp, :connection, :command, :stop], %{duration: duration}, %{method: method}) do
    "CDP #{method} in #{format_duration(duration)}"
  end

  defp format_event([:light_cdp, :page, :step], _measurements, %{step: step} = metadata) do
    detail =
      metadata
      |> Map.drop([:step])
      |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{inspect(v)}" end)

    if detail == "", do: "  · #{step}", else: "  · #{step} (#{detail})"
  end

  defp format_event(event, _measurements, _metadata) do
    inspect(event)
  end

  defp format_detail(:navigate, %{url: url}), do: url
  defp format_detail(:click, %{selector: s}), do: s
  defp format_detail(:fill, %{selector: s}), do: s
  defp format_detail(:evaluate, %{expression: e}), do: String.slice(e, 0..60)
  defp format_detail(:submit, %{form_selector: s}), do: s
  defp format_detail(:wait_for_selector, %{selector: s}), do: s
  defp format_detail(_op, _meta), do: ""

  defp format_duration(duration) do
    us = System.convert_time_unit(duration, :native, :microsecond)
    "#{Float.round(us / 1000, 1)}ms"
  end
end
