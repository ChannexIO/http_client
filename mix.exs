defmodule HTTPClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :http_client,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {HTTPClient.Application, []}
    ]
  end

  defp deps do
    [
      {:nimble_options, "~> 0.2"},
      {:httpoison, "~> 1.6"},
      {:finch, "~> 0.2"},
      {:telemetry, "~> 0.4"},
      {:bypass, "~> 1.0", only: :test}
    ]
  end
end
