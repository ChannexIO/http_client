defmodule HTTPClient.Adapter do
  @moduledoc """
  An HTTP client behaviour definition.

  Adapters that implement the HTTP client behaviour must support the following
  list of functions:

    * `c:request/5` - Issues an HTTP request with the given method to the given url
    * `c:get/3` - issues GET request to the given url
    * `c:post/4` - issues POST request to the given url
    * `c:put/4` - issues PUT request to the given url
    * `c:patch/4` - issues PATCH request to the given url
    * `c:delete/3` - issues DELETE request to the given url

  All functions must return response defined in `t:response/0`.
  """

  alias HTTPClient.Adapters.{Finch, HTTPoison}
  alias HTTPClient.{Error, Response, Telemetry}
  alias NimbleOptions.ValidationError

  @typedoc """
  A response to a request.

  Unified for all adapter implementations.
  """
  @type response() :: {:ok, HTTPClient.Response.t()} | {:error, HTTPClient.Error.t()}

  @typedoc "An HTTP request method represented as an `atom()` or a `String.t()`."
  @type method() :: Finch.method() | HTTPoison.method()

  @typedoc "A Uniform Resource Locator, the address of a resource on the Web."
  @type url() :: Finch.url() | HTTPoison.url()

  @typedoc "A body associated with a request."
  @type body() :: Finch.body() | HTTPoison.body()

  @typedoc """
  HTTP headers.

  Headers are sent and received as lists of two-element tuples containing two strings,
  the header name and header value.
  """
  @type headers() :: Finch.headers() | HTTPoison.headers()

  @typedoc "Keyword list of options supported by adapter implementation."
  @type options() :: Finch.options() | HTTPoison.options()

  @doc """
  Issues a GET request to the given url.

  See `c:request/5` for more detailed information.
  """
  @callback get(url(), headers(), options()) :: response()

  @doc """
  Issues a POST request to the given url.

  See `c:request/5` for more detailed information.
  """
  @callback post(url(), body(), headers(), options()) :: response()

  @doc """
  Issues a PUT request to the given url.

  See `c:request/5` for more detailed information.
  """
  @callback put(url(), body(), headers(), options()) :: response()

  @doc """
  Issues a PATCH request to the given url.

  See `c:request/5` for more detailed information.
  """
  @callback patch(url(), body(), headers(), options()) :: response()

  @doc """
  Issues a DELETE request to the given url.

  See `c:request/5` for more detailed information.
  """
  @callback delete(url(), headers(), options()) :: response()

  @doc """
  Issues an HTTP request with the given method to the given url.

  This function is usually used indirectly by `get/3`, `post/4`, `put/4`, etc

  Args:
    * `method` - HTTP method as an atom (`:get`, `:post`, `:put`, `:delete`, etc.)
    * `url` - target url as a binary string
    * `body` - request body
    * `headers` - HTTP headers as an keyword (e.g., `[{"Accept", "application/json"}]`)
    * `options` - Keyword list of options

  Returns `{:ok, HTTPClient.Response.t()}` if the request is successful,
  `{:error, HTTPClient.Error.t()}` otherwise.
  """
  @callback request(method(), url(), body(), headers(), options()) :: response()

  @config_schema [
    adapter: [
      type: {:in, [:finch, :httpoison]},
      doc: "Implementation of adapter to use.",
      default: :httpoison
    ]
  ]

  @doc """
  Sets HTTP client implementation adapter based on the use options.

  ### Using options
  #{NimbleOptions.docs(@config_schema)}
  """
  def set(opts) do
    with {:ok, valid} <- NimbleOptions.validate(opts, @config_schema) do
      adapter_mod(valid[:adapter])
    else
      {:error, %ValidationError{message: message}} ->
        raise ArgumentError, "got invalid configuration for HTTPClient #{message}"
    end
  end

  @doc false
  def request(adapter, method, url, body, headers, options) do
    perform(adapter, :request, [method, url, body, headers, options])
  end

  @doc false
  def get(adapter, url, headers, options) do
    perform(adapter, :get, [url, headers, options])
  end

  @doc false
  def post(adapter, url, body, headers, options) do
    perform(adapter, :post, [url, body, headers, options])
  end

  @doc false
  def put(adapter, url, body, headers, options) do
    perform(adapter, :put, [url, body, headers, options])
  end

  @doc false
  def patch(adapter, url, body, headers, options) do
    perform(adapter, :patch, [url, body, headers, options])
  end

  @doc false
  def delete(adapter, url, headers, options) do
    perform(adapter, :delete, [url, headers, options])
  end

  defp perform(adapter, method, args) do
    metadata = %{adapter: adapter, args: args, method: method}
    start_time = Telemetry.start(:request, metadata)

    case apply(adapter, method, args) do
      {:ok, %Response{status: status}} = response ->
        metadata = Map.put(metadata, :status_code, status)
        Telemetry.stop(:request, start_time, metadata)
        response

      {:error, %Error{reason: reason}} = error_response ->
        metadata = Map.put(metadata, :error, reason)
        Telemetry.stop(:request, start_time, metadata)
        error_response
    end
  end

  defp adapter_mod(:finch), do: HTTPClient.Adapters.Finch
  defp adapter_mod(:httpoison), do: HTTPClient.Adapters.HTTPoison
end
