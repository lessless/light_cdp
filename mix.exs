defmodule LightCDP.MixProject do
  use Mix.Project

  def project do
    [
      app: :light_cdp,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: "Minimal CDP (Chrome DevTools Protocol) client for Lightpanda. No Node.js required.",
      package: package(),
      source_url: "https://github.com/lessless/light_cdp"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/lessless/light_cdp"}
    ]
  end

  defp docs do
    [
      main: "LightCDP",
      source_url: "https://github.com/lessless/light_cdp"
    ]
  end

  defp deps do
    [
      {:websockex, "~> 0.4"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:erlexec, "~> 2.0"},
      {:telemetry, "~> 1.0"},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false}
    ]
  end
end
