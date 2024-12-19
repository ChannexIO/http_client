defmodule HTTPClient.Adapters.Finch do
  @moduledoc """
  Implementation of `HTTPClient.Adapter` behaviour using Finch HTTP client.
  """

  alias HTTPClient.{Request, Response}

  @type method() :: Finch.Request.method()
  @type url() :: Finch.Request.url()
  @type headers() :: Finch.Request.headers()
  @type body() :: Finch.Request.body()
  @type options() :: keyword()

  @doc """
  Performs the request using `Finch`.
  """
  def perform_request(request) do
    {request, options} = prepare_options(request)

    maybe_log_operation(request, "started")

    try do
      request.method
      |> Finch.build(request.url, request.headers, request.body)
      |> Finch.request(request.private.finch_name, options)
      |> case do
        {:ok, %{status: status, body: body, headers: headers}} ->
          maybe_log_operation(request, "done")

          {request,
           Response.new(status: status, body: body, headers: headers, request_url: request.url)}

        {:error, exception} ->
          log_operation(request, Exception.format(:error, exception))
          {request, exception}
      end
    rescue
      exception ->
        log_operation(request, Exception.format(:error, exception))
        {request, exception}
    end
  end

  def maybe_log_operation(request, message) do
    with true <- log_operation?() do
      log_operation(request, message)
    end
  end

  def log_operation(request, message) do
    IO.inspect("proxy: #{Jason.encode!(request.private.proxy)}. #{message}",
      label: "#{request.private.finch_name} #{request.private.logger_context}"
    )
  end

  @doc false
  def proxy(request) do
    tls_versions = Map.get(request.options, :tls_versions, [:"tlsv1.2", :"tlsv1.3"])
    {finch_name, used_proxy} = get_client(tls_versions)

    request
    |> Request.put_private(:finch_name, finch_name)
    |> Request.put_private(:proxy, used_proxy)
  end

  defp prepare_options(request) do
    {logger_context, options} = Map.pop(request.options, :logger_context)

    {Request.put_private(request, :logger_context, logger_context),
     Enum.map(options, &normalize_option/1)}
  end

  defp normalize_option({:timeout, value}), do: {:pool_timeout, value}
  defp normalize_option({:recv_timeout, value}), do: {:receive_timeout, value}
  defp normalize_option({key, value}), do: {key, value}

  defp get_client(tls_versions) do
    :http_client
    |> Application.get_env(:proxy)
    |> get_client_name(tls_versions)
  end

  defp get_client_name(nil, _tls_versions), do: {HTTPClient.Finch, {}}

  defp get_client_name(proxies, tls_versions) when is_list(proxies) do
    proxies
    |> Enum.random()
    |> get_client_name(tls_versions)
  end

  defp get_client_name(proxy, tls_versions) when is_map(proxy) do
    name = custom_pool_name(proxy)
    composed_proxy = compose_proxy(proxy)

    pools = %{
      default: [
        conn_opts: [
          proxy: composed_proxy,
          proxy_headers: compose_proxy_headers(proxy),
          transport_opts: [versions: tls_versions]
        ]
      ]
    }

    child_spec = {Finch, name: name, pools: pools}

    case DynamicSupervisor.start_child(HTTPClient.FinchSupervisor, child_spec) do
      {:ok, _} -> {name, composed_proxy}
      {:error, {:already_started, _}} -> {name, composed_proxy}
    end
  end

  defp compose_proxy_headers(%{opts: opts}) do
    Keyword.get(opts, :proxy_headers, [])
  end

  defp compose_proxy_headers(_), do: []

  defp compose_proxy(proxy) do
    {proxy.scheme, proxy.address, to_integer(proxy.port), proxy.opts}
  end

  defp to_integer(term) when is_integer(term), do: term
  defp to_integer(term) when is_binary(term), do: String.to_integer(term)

  defp custom_pool_name(opts) do
    name =
      opts
      |> :erlang.term_to_binary()
      |> :erlang.md5()
      |> Base.url_encode64(padding: false)

    Module.concat(HTTPClient.FinchSupervisor, "Pool_#{name}")
  end

  defp log_operation? do
    Application.get_env(:http_client, :log_operation, false)
  end
end
