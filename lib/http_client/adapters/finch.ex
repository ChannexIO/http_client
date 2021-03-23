defmodule HTTPClient.Adapters.Finch do
  @moduledoc """
  Implementation of `HTTPClient.Adapter` behaviour using Finch HTTP client.
  """

  alias HTTPClient.{Error, Response}

  @type method() :: Finch.Request.method()
  @type url() :: Finch.Request.url()
  @type headers() :: Finch.Request.headers()
  @type body() :: Finch.Request.body()
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
    {params, options} = Keyword.pop(options, :params)
    {basic_auth, options} = Keyword.pop(options, :basic_auth)

    url = build_request_url(url, params)
    headers = add_basic_auth_header(headers, basic_auth)
    options = prepare_options(options)

    method
    |> Finch.build(url, headers, body)
    |> Finch.request(FinchHTTPClient, options)
    |> case do
      {:ok, %{status: status, body: body, headers: headers}} ->
        {:ok, %Response{status: status, body: body, headers: headers, request_url: url}}

      {:error, error} ->
        {:error, %Error{reason: error.reason}}
    end
  end

  defp build_request_url(url, nil), do: url

  defp build_request_url(url, params) do
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

  defp prepare_options(options) do
    Enum.map(options, &normalize_option/1)
  end

  defp normalize_option({:timeout, value}), do: {:pool_timeout, value}
  defp normalize_option({:recv_timeout, value}), do: {:receive_timeout, value}
  defp normalize_option({key, value}), do: {key, value}
end
