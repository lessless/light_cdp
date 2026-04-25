defmodule LightCDP.Protocol do
  @moduledoc """
  JSON encoding/decoding for CDP messages.

  CDP uses JSON-RPC over WebSocket with three message types:

    * **Command** — `%{id: 1, method: "Page.navigate", params: %{url: "..."}}`
    * **Response** — `%{id: 1, result: %{...}}` or `%{id: 1, error: %{...}}`
    * **Event** — `%{method: "Page.loadEventFired", params: %{...}}`
  """

  @doc """
  Encodes a CDP command as a JSON string.

      iex> LightCDP.Protocol.encode(1, "Page.navigate", %{url: "https://example.com"})
      |> Jason.decode!()
      |> Map.keys() |> Enum.sort()
      ["id", "method", "params"]
  """
  def encode(id, method, params \\ %{}) do
    Jason.encode!(%{id: id, method: method, params: params})
  end

  @doc """
  Decodes a CDP JSON message into a tagged tuple.

  Returns one of:

    * `{:response, id, result}` — successful command response
    * `{:error, id, error}` — failed command response
    * `{:event, method, params}` — unsolicited event
  """
  def decode(json) do
    case Jason.decode!(json) do
      %{"id" => id, "error" => error} -> {:error, id, error}
      %{"id" => id, "result" => result} -> {:response, id, result}
      %{"method" => method, "params" => params} -> {:event, method, params}
    end
  end
end
