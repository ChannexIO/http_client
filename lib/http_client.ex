defmodule HTTPClient do
  @moduledoc """
  Facade for HTTP client.

  This module is meant to be `use`'d in custom modules in order to wrap the
  functionalities provided by supported HTTP clients.
  """

  alias HTTPClient.Adapter

  defmacro __using__(opts) do
    quote do
      opts = unquote(opts)
      @adapter Adapter.set(opts)

      @doc """
      Issues a GET request to the given url.

      See `request/5` for more detailed information.
      """
      @spec get(Adapter.url(), Adapter.header(), Adapter.options()) :: Adapter.response()
      def get(url, headers, options) do
        @adapter.get(url, headers, options)
      end

      @doc """
      Issues a POST request to the given url.

      See `request/5` for more detailed information.
      """
      @spec post(Adapter.url(), Adapter.body(), Adapter.header(), Adapter.options()) ::
              Adapter.response()
      def post(url, body, headers, options) do
        @adapter.post(url, body, headers, options)
      end

      @doc """
      Issues a PUT request to the given url.

      See `request/5` for more detailed information.
      """
      @spec put(Adapter.url(), Adapter.body(), Adapter.header(), Adapter.options()) ::
              Adapter.response()
      def put(url, body, headers, options) do
        @adapter.put(url, body, headers, options)
      end

      @doc """
      Issues a PATCH request to the given url.

      See `request/5` for more detailed information.
      """
      @spec patch(Adapter.url(), Adapter.body(), Adapter.header(), Adapter.options()) ::
              Adapter.response()
      def patch(url, body, headers, options) do
        @adapter.patch(url, body, headers, options)
      end

      @doc """
      Issues a DELETE request to the given url.

      See `request/5` for more detailed information.
      """
      @spec delete(Adapter.url(), Adapter.header(), Adapter.options()) :: Adapter.response()
      def delete(url, headers, options) do
        @adapter.delete(url, headers, options)
      end

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
      @spec request(
              Adapter.method(),
              Adapter.url(),
              Adapter.body(),
              Adapter.header(),
              Adapter.options()
            ) :: Adapter.response()
      def request(method, url, body, headers, options) do
        @adapter.request(method, url, body, headers, options)
      end
    end
  end
end
