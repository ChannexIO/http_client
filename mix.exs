defmodule HTTPClient.MixProject do
  use Mix.Project

  @name "HTTPClient"
  @version "0.3.8"
  @repo_url "https://github.com/ChannexIO/http_client"

  def project do
    [
      app: :http_client,
      version: @version,
      elixir: "~> 1.12",
      description: "Facade for HTTP client.",
      docs: docs(),
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
      {:nimble_options, "~> 1.1"},
      {:httpoison, "~> 2.2"},
      {:finch, "~> 0.19"},
      {:telemetry, "~> 1.3"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.17", only: :test, override: true},
      {:plug_cowboy, "~> 2.7", only: :test, override: true},
      {:bypass, "~> 2.1", only: :test},
      {:ex_doc, "~> 0.37.3", only: :dev, runtime: false}
    ]
  end

  def docs do
    [
      source_ref: "v#{@version}",
      source_url: @repo_url,
      main: @name
    ]
  end
end
