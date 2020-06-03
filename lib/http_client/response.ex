defmodule HTTPClient.Response do
  @moduledoc """
  A response to a request.
  """

  defstruct [:status, body: "", headers: []]

  @type t :: %__MODULE__{
          status: Mint.Types.status(),
          body: binary(),
          headers: Mint.Types.headers()
        }
end
