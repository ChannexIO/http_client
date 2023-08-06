defmodule HTTPClient.Adapters.HTTPoison do
  @moduledoc """
  Implementation of `HTTPClient.Adapter` behaviour using HTTPoison HTTP client.
  """

  alias HTTPClient.Response

  @type method() :: HTTPoison.Request.method()
  @type url() :: HTTPoison.Request.url()
  @type headers() :: HTTPoison.Request.headers()
  @type body() :: HTTPoison.Request.body()
  @type options() :: HTTPoison.Request.options()

  @doc """
  Performs the request using `HTTPoison`.
  """
  def perform_request(request) do
    options = Map.to_list(request.options)

    case HTTPoison.request(request.method, request.url, request.body, request.headers, options) do
      {:ok, %{status_code: status, body: body, headers: headers}} ->
        {request,
         Response.new(status: status, body: body, headers: headers, request_url: request.url)}

      {:error, exception} ->
        {request, exception}
    end
  end

  @doc false
  def proxy(request) do
    update_in(request.options, &setup_proxy/1)
  end

  defp setup_proxy(options) do
    case Application.get_env(:http_client, :proxy, nil) do
      nil -> options
      proxies -> add_proxy(options, proxies)
    end
  end

  defp add_proxy(options, proxy) when is_map(proxy) do
    Map.put(options, :proxy, "#{proxy.scheme}://#{proxy.address}:#{proxy.port}")
  end

  defp add_proxy(options, proxies) when is_list(proxies) do
    add_proxy(options, Enum.random(proxies))
  end
end
