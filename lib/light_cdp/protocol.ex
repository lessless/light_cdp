defmodule LightCDP.Protocol do
  def encode(id, method, params \\ %{}) do
    Jason.encode!(%{id: id, method: method, params: params})
  end

  def decode(json) do
    case Jason.decode!(json) do
      %{"id" => id, "error" => error} -> {:error, id, error}
      %{"id" => id, "result" => result} -> {:response, id, result}
      %{"method" => method, "params" => params} -> {:event, method, params}
    end
  end
end
