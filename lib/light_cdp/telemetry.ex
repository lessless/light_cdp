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

  ## Default logger

      LightCDP.Telemetry.attach_default_logger(level: :debug)
  """

  require Logger

  @handler_id "light-cdp-default-logger"

  @page_operations ~w(navigate evaluate click fill submit screenshot content url wait_for_selector wait_for_navigation)a

  @doc """
  Returns all telemetry event names emitted by LightCDP.
  """
  def events do
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
  Attaches a default Logger handler for all LightCDP telemetry events.

  ## Options

    * `:level` - log level (default: `:debug`)
  """
  def attach_default_logger(opts \\ []) do
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
