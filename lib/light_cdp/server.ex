defmodule LightCDP.Server do
  def start(opts \\ []) do
    binary = opts[:binary] || default_binary()
    port_number = opts[:port] || 9222
    host = opts[:host] || "127.0.0.1"

    ensure_exec_started()

    timeout = opts[:timeout] || 30

    {:ok, pid, os_pid} =
      :exec.run(
        [binary, "serve", "--host", host, "--port", to_string(port_number),
         "--timeout", to_string(timeout)],
        [:stdout, :stderr, :monitor]
      )

    endpoint = "http://#{host}:#{port_number}"
    wait_for_ready!(endpoint)
    {:ok, {pid, os_pid}, endpoint}
  end

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
