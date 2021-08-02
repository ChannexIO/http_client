defmodule HTTPClient.Error do
  @moduledoc """
  An error of a request.
  """

  defstruct [:reason]

  @type t :: %__MODULE__{reason: term()}

  defimpl Jason.Encoder do
    def encode(struct, opts) do
      struct
      |> Map.from_struct()
      |> Jason.Encode.map(opts)
    end
  end
end
