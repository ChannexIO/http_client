defmodule HTTPClient.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [] ++ HTTPClient.Adapters.Finch.Config.children()

    opts = [strategy: :one_for_one, name: HTTPClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
