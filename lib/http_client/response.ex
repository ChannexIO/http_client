defmodule HTTPClient.Response do
  @moduledoc """
  A response to a request.
  """

  defstruct [:request_url, :status, body: "", headers: []]

  @type t :: %__MODULE__{
          body: binary(),
          headers: keyword(),
          request_url: binary(),
          status: non_neg_integer()
        }
end
