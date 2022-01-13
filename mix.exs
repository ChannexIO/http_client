defmodule HTTPClient.MixProject do
  use Mix.Project

  @name "HTTPClient"
  @version "0.3.6"
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
      {:nimble_options, "~> 0.4"},
      {:httpoison, "~> 1.8"},
      {:finch, "~> 0.10.2"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.3"},
      {:plug, "~> 1.12", only: :test, override: true},
      {:plug_cowboy, "~> 2.5", only: :test, override: true},
      {:bypass, "~> 2.1", only: :test},
      {:ex_doc, "~> 0.27.3", only: :dev, runtime: false}
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
