defmodule HTTPClient.Adapters.HTTPoison do
  @moduledoc """
  Implementation of `HTTPClient.Adapter` behaviour using HTTPoison HTTP client.
  """

  alias HTTPClient.{Error, Response}

  @type method() :: HTTPoison.Request.method()
  @type url() :: HTTPoison.Request.url()
  @type headers() :: HTTPoison.Request.headers()
  @type body() :: HTTPoison.Request.body()
  @type options() :: HTTPoison.Request.options()

  @behaviour HTTPClient.Adapter

  @delay 1000

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

  defp perform_request(method, url, headers, body, options, attempt \\ 0) do
    options = setup_proxy(options)
    options = add_basic_auth_option(options, options[:basic_auth])

    case HTTPoison.request(method, url, body, headers, options) do
      {:ok, %{status_code: status, body: body, headers: headers, request: request}} ->
        {:ok, %Response{status: status, body: body, headers: headers, request_url: request.url}}

      {:error, %HTTPoison.Error{id: nil, reason: :proxy_error}} ->
        case attempt < 5 do
          true ->
            Process.sleep(attempt * @delay)
            perform_request(method, url, headers, body, options, attempt + 1)

          false ->
            {:error, %Error{reason: :proxy_error}}
        end

      {:error, error} ->
        {:error, %Error{reason: error.reason}}
    end
  end

  defp add_basic_auth_option(options, nil), do: options

  defp add_basic_auth_option(options, {username, password}) do
    put_in(options, [:hackney], basic_auth: {username, password})
  end

  defp setup_proxy(options) do
    case Application.get_env(:http_client, :proxy, nil) do
      nil -> options
      proxies -> add_proxy(options, proxies)
    end
  end

  defp add_proxy(options, proxy) when is_map(proxy) do
    Keyword.put(options, :proxy, "#{proxy.scheme}://#{proxy.address}:#{proxy.port}")
  end

  defp add_proxy(options, proxies) when is_list(proxies) do
    add_proxy(options, Enum.random(proxies))
  end
end
