defmodule HTTPClient.MixProject do
  use Mix.Project

  @name "HTTPClient"
  @version "0.1.0"
  @repo_url "https://github.com/ChannexIO/http_client"

  def project do
    [
      app: :http_client,
      version: @version,
      elixir: "~> 1.7",
      description: "Facade for HTTP client.",
      start_permanent: Mix.env() == :prod,
      name: @name,
      source_url: @repo_url,
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
