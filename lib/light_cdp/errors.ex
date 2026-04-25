defmodule LightCDP.ElementNotFoundError do
  @moduledoc "Raised when a CSS selector matches no element in the DOM."
  defexception [:selector, :message]

  def new(selector) do
    %__MODULE__{selector: selector, message: "Element not found: #{selector}"}
  end
end

defmodule LightCDP.TimeoutError do
  @moduledoc "Raised when an operation exceeds its deadline."
  defexception [:operation, :timeout_ms, :message]

  def new(opts \\ []) do
    operation = opts[:operation]
    timeout_ms = opts[:timeout_ms]

    message =
      case operation do
        nil -> "Operation timed out"
        op -> "#{op} timed out" <> if(timeout_ms, do: " after #{timeout_ms}ms", else: "")
      end

    %__MODULE__{operation: operation, timeout_ms: timeout_ms, message: message}
  end
end

defmodule LightCDP.JavaScriptError do
  @moduledoc "Raised when a JavaScript expression throws an exception."
  defexception [:message]

  def new(description) do
    %__MODULE__{message: description}
  end
end

defmodule LightCDP.CDPError do
  @moduledoc "Raised when the CDP protocol returns an error response."
  defexception [:code, :message]

  def new(code, message) do
    %__MODULE__{code: code, message: "CDP error #{code}: #{message}"}
  end
end

defmodule LightCDP.ConnectionError do
  @moduledoc "Raised when connecting to a CDP endpoint fails."
  defexception [:reason, :message]

  def new(reason) do
    %__MODULE__{reason: reason, message: "Connection failed: #{inspect(reason)}"}
  end
end
