defmodule HTTPClient.Adapters.HTTPoison do
  @moduledoc """
  Implementation of `HTTPClient.Adapter` behaviour using HTTPoison HTTP client.
  """

  alias HTTPClient.Request
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
    {_logger_context, options} = Map.pop(request.options, :logger_context)
    options = Map.to_list(options)

    case HTTPoison.request(request.method, request.url, request.body, request.headers, options) do
      {:ok, %{status_code: status, body: body, headers: headers}} ->
        response =
          [status: status, body: body, headers: headers, request_url: request.url]
          |> Response.new()
          |> Response.put_private(:proxy, Request.get_private(request, :proxy))

        {request, response}

      {:error, exception} ->
        {request, exception}
    end
  end

  @doc false
  def proxy(request) do
    {used_proxy, options} = setup_proxy(request.options)

    request
    |> Map.put(:options, options)
    |> Request.put_private(:proxy, used_proxy)
  end

  # A per-request `:proxy` option (a proxy map, a list of them, or nil for a
  # direct connection) overrides the globally configured `:proxy` list. When the
  # option is absent the global config is used, preserving the default behaviour.
  defp setup_proxy(options) do
    case Map.fetch(options, :proxy) do
      {:ok, proxy} -> add_proxy(options, proxy)
      :error -> setup_proxy(options, Application.get_env(:http_client, :proxy, nil))
    end
  end

  defp setup_proxy(options, nil), do: {nil, options}
  defp setup_proxy(options, proxies), do: add_proxy(options, proxies)

  defp add_proxy(options, nil), do: {nil, Map.delete(options, :proxy)}
  defp add_proxy(options, []), do: {nil, Map.delete(options, :proxy)}

  defp add_proxy(options, proxy) when is_map(proxy) do
    url = "#{proxy.scheme}://#{proxy.address}:#{proxy.port}"
    {url, Map.put(options, :proxy, url)}
  end

  defp add_proxy(options, proxies) when is_list(proxies) do
    add_proxy(options, Enum.random(proxies))
  end
end
