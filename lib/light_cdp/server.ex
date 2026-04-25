defmodule LightCDP.Server do
  @moduledoc """
  Manages the Lightpanda OS process via `erlexec`.

  Starts the binary with `serve` mode, waits for the CDP server to be ready,
  and provides clean shutdown via SIGTERM.

  Typically not used directly — `LightCDP.start/1` handles this.

  ## Binary path resolution

  1. `start(binary: "/path/to/lightpanda")`
  2. `Application.get_env(:light_cdp, :lightpanda_path)`
  3. `~/.local/bin/lightpanda`
  """

  @doc """
  Starts a Lightpanda CDP server.

  Returns `{:ok, server, endpoint}` where `server` is passed to `stop/1`
  and `endpoint` is the HTTP base URL (e.g. `"http://127.0.0.1:9222"`).

  ## Options

    * `:binary` - path to the Lightpanda binary
    * `:port` - CDP server port (default: `9222`)
    * `:host` - CDP server host (default: `"127.0.0.1"`)
    * `:timeout` - Lightpanda inactivity timeout in seconds (default: `30`)
  """
  def start(opts \\ []) do
    binary = opts[:binary] || default_binary()
    port_number = opts[:port] || 9222
    host = opts[:host] || "127.0.0.1"

    ensure_exec_started()

    timeout = opts[:timeout] || 30

    {:ok, pid, os_pid} =
      :exec.run(
        [binary, "serve", "--host", host, "--port", to_string(port_number), "--timeout", to_string(timeout)],
        [:stdout, :stderr, :monitor]
      )

    endpoint = "http://#{host}:#{port_number}"
    wait_for_ready!(endpoint)
    {:ok, {pid, os_pid}, endpoint}
  end

  @doc """
  Stops a Lightpanda instance by sending SIGTERM to the OS process.
  """
  def stop({_pid, os_pid}) do
    :exec.kill(os_pid, :sigterm)
    :ok
  catch
    _, _ -> :ok
  end

  defp ensure_exec_started do
    case :exec.start() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  defp default_binary do
    Application.get_env(:light_cdp, :lightpanda_path, default_path())
  end

  defp default_path do
    Path.join([System.get_env("HOME"), ".local", "bin", "lightpanda"])
  end

  defp wait_for_ready!(endpoint, attempts \\ 30) do
    case Req.get(endpoint <> "/json/version", retry: false) do
      {:ok, %{status: 200}} ->
        :ok

      _ when attempts > 0 ->
        Process.sleep(100)
        wait_for_ready!(endpoint, attempts - 1)

      _ ->
        raise "Lightpanda did not start at #{endpoint}"
    end
  end
end
