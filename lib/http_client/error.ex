defmodule HTTPClient.Error do
  @moduledoc """
  An error of a request.
  """

  @type t() :: %__MODULE__{reason: atom()}

  defexception [:reason]

  @impl true
  def exception(reason) when is_atom(reason) do
    %__MODULE__{reason: reason}
  end

  @impl true
  def message(%__MODULE__{reason: reason}) do
    "#{reason}"
  end

  defimpl Jason.Encoder do
    def encode(struct, opts) do
      struct
      |> Map.from_struct()
      |> Jason.Encode.map(opts)
    end
  end
end
