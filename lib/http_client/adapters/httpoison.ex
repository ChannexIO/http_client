defmodule HttpClient.Adapters.HTTPoison do
  @moduledoc """
  Implementation of `HttpClient.Adapter` behaviour using HTTPoison HTTP client.
  """

  alias HttpClient.{Error, Response, Telemetry}

  @type method() :: HTTPoison.Request.method()
  @type url() :: HTTPoison.Request.url()
  @type headers() :: HTTPoison.Request.headers()
  @type body() :: HTTPoison.Request.body()
  @type options() :: HTTPoison.Request.options()

  @behaviour HttpClient.Adapter

  @impl true
  def request(method, url, body, headers, options) do
    perform_request(method, url, headers, body, options)
  end

  @impl true
  def get(url, headers, options) do
    perform_request(:get, url, headers, "", options)
  end

  @impl true
  def post(url, body, headers, options) do
    perform_request(:post, url, headers, body, options)
  end

  @impl true
  def put(url, body, headers, options) do
    perform_request(:put, url, headers, body, options)
  end

  @impl true
  def patch(url, body, headers, options) do
    perform_request(:patch, url, headers, body, options)
  end

  @impl true
  def delete(url, headers, options) do
    perform_request(:delete, url, headers, "", options)
  end

  defp perform_request(method, url, headers, body, options) do
    options = add_basic_auth_option(options, options[:basic_auth])

    metadata = %{
      method: method,
      url: url,
      options: options
    }

    start_time = Telemetry.start(:request, metadata)

    case HTTPoison.request(method, url, body, headers, options) do
      {:ok, %{status_code: status, body: body, headers: headers}} ->
        metadata = Map.put(metadata, :status_code, status)
        Telemetry.stop(:request, start_time, metadata)
        {:ok, %Response{status: status, body: body, headers: headers}}

      {:error, error} ->
        metadata = Map.put(metadata, :error, error)
        Telemetry.stop(:request, start_time, metadata)
        {:error, %Error{reason: error.reason}}
    end
  end

  defp add_basic_auth_option(options, nil), do: options

  defp add_basic_auth_option(options, {username, password}) do
    put_in(options, [:hackney], basic_auth: {username, password})
  end
end
