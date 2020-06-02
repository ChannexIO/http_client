defmodule HTTPClient.Error do
  @moduledoc """
  An error of a request.
  """

  alias __MODULE__

  defstruct [:reason]

  @type t :: %Error{reason: term()}
end
