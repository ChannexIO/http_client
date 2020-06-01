defmodule HttpClient.Adapter do
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

  alias HttpClient.Adapters.{Finch, HTTPoison}

  @type response() :: {:ok, HttpClient.Response.t()} | {:error, HttpClient.Error.t()}

  @type method() :: Finch.method() | HTTPoison.method()
  @type url() :: Finch.url() | HTTPoison.url()
  @type headers() :: Finch.headers() | HTTPoison.headers()
  @type body() :: Finch.body() | HTTPoison.body()
  @type options() :: Finch.options() | HTTPoison.options()

  @callback request(method(), url(), body(), headers(), options()) :: response()
  @callback get(url(), headers(), options()) :: response()
  @callback post(url(), body(), headers(), options()) :: response()
  @callback put(url(), body(), headers(), options()) :: response()
  @callback patch(url(), body(), headers(), options()) :: response()
  @callback delete(url(), headers(), options()) :: response()

  @config_schema [
    adapter: [
      type: {:one_of, [:finch, :httpoison]},
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
      choose_adapter(valid[:adapter])
    else
      {:error, reason} ->
        raise ArgumentError, "got invalid configuration for HttpClient #{reason}"
    end
  end

  defp choose_adapter(:finch), do: HttpClient.Adapters.Finch
  defp choose_adapter(:httpoison), do: HttpClient.Adapters.HTTPoison
end
