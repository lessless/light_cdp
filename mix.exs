defmodule LightCDP.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :light_cdp,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      aliases: aliases(),
      description: "Minimal CDP (Chrome DevTools Protocol) client for Lightpanda. No Node.js required.",
      package: package(),
      source_url: "https://github.com/lessless/light_cdp"
    ]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

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
      source_url: "https://github.com/lessless/light_cdp",
      extras: [
        "guides/observability.md",
        "examples/sample.md"
      ]
    ]
  end

  defp deps do
    [
      {:websockex, "~> 0.4"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:erlexec, "~> 2.0"},
      {:telemetry, "~> 1.0"},
      {:opentelemetry, "~> 1.4", optional: true},
      {:opentelemetry_api, "~> 1.3", optional: true},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:tidewave, "~> 0.4", only: :dev},
      {:bandit, "~> 1.8", only: :dev},
      {:git_ops, "~> 2.6", only: :dev}
    ]
  end

  defp aliases do
    [
      tidewave: "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 40001) end)'",
      ci: ["format --check-formatted", "compile --warnings-as-errors", "test"]
    ]
  end
end
