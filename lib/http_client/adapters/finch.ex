defmodule HTTPClient.Adapters.Finch do
  @moduledoc """
  Implementation of `HTTPClient.Adapter` behaviour using Finch HTTP client.
  """

  alias HTTPClient.{Error, Response, Telemetry}

  @type method() :: Finch.http_method()
  @type url() :: Finch.url()
  @type headers() :: Mint.Types.headers()
  @type body() :: Finch.body()
  @type options() :: keyword()

  @behaviour HTTPClient.Adapter

  @impl true
  def request(method, url, body, headers, options) do
    perform_request(method, url, headers, body, options)
  end

  @impl true
  def get(url, headers, options) do
    perform_request(:get, url, headers, nil, options)
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
    perform_request(:delete, url, headers, nil, options)
  end

  defp perform_request(method, url, headers, body, options) do
    url = build_request_url(url, options[:params])
    headers = add_basic_auth_header(headers, options[:basic_auth])

    metadata = %{
      method: method,
      url: url,
      options: options
    }

    start_time = Telemetry.start(:request, metadata)

    case Finch.request(FinchHTTPClient, method, url, headers, body, options) do
      {:ok, %{status: status, body: body, headers: headers}} ->
        metadata = Map.put(metadata, :status_code, status)
        Telemetry.stop(:request, start_time, metadata)
        {:ok, %Response{status: status, body: body, headers: headers}}

      {:error, error} ->
        metadata = Map.put(metadata, :error, error)
        Telemetry.stop(:request, start_time, metadata)
        {:error, %Error{reason: error.reason}}
    end
  end

  def build_request_url(url, nil), do: url

  def build_request_url(url, params) do
    cond do
      Enum.count(params) === 0 -> url
      URI.parse(url).query -> url <> "&" <> URI.encode_query(params)
      true -> url <> "?" <> URI.encode_query(params)
    end
  end

  defp add_basic_auth_header(headers, {username, password}) do
    credentials = Base.encode64("#{username}:#{password}")
    [{"Authorization", "Basic " <> credentials} | headers || []]
  end

  defp add_basic_auth_header(headers, _basic_auth), do: headers
end
