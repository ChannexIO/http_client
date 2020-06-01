defmodule HttpClient.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Finch, name: FinchHttpClient}
    ]

    opts = [strategy: :one_for_one, name: HttpClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
