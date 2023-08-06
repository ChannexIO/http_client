defmodule HTTPClient.Response do
  @moduledoc """
  A response to a request.

  Fields:

    * `:status` - the HTTP status code

    * `:headers` - the HTTP response headers

    * `:request_url` - the URL of request

    * `:body` - the HTTP response body

    * `:private` - a map reserved for internal use.
  """

  defstruct [:request_url, :status, body: "", headers: [], private: %{}]

  @type t() :: %__MODULE__{
          body: binary(),
          headers: keyword(),
          private: map(),
          request_url: binary(),
          status: non_neg_integer()
        }

  @doc """
  Builds `HTTPClient.Response` struct with provided data.
  """
  def new(data) do
    struct(%__MODULE__{}, data)
  end

  @doc """
  Gets the value for a specific private `key`.
  """
  def get_private(response, key, default \\ nil) when is_atom(key) do
    Map.get(response.private, key, default)
  end

  @doc """
  Assigns a private `key` to `value`.
  """
  def put_private(response, key, value) when is_atom(key) do
    put_in(response.private[key], value)
  end
end
