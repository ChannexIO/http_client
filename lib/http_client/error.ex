defmodule HTTPClient.Error do
  @moduledoc """
  An error of a request.
  """

  defstruct [:reason]

  @type t :: %__MODULE__{reason: term()}
end
