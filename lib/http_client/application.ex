defmodule HTTPClient.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Finch, name: HTTPClient.Finch},
      {DynamicSupervisor, strategy: :one_for_one, name: HTTPClient.FinchSupervisor}
    ]

    opts = [strategy: :one_for_one, name: HTTPClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
