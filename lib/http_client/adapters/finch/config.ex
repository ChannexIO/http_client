defmodule HTTPClient.Adapters.Finch.Config do
  @moduledoc """
  Provide Application.children for Application supervisor
  """

  @doc """
  Returns list of childrens for Application supervisor
  """
  def children do
    case Application.get_env(:http_client, :proxy, nil) do
      nil -> [{Finch, name: FinchHTTPClient}]
      proxies -> generate_finch_proxies(proxies)
    end
  end

  defp generate_finch_proxies(proxy) when is_map(proxy) do
    [
      {
        Finch,
        name: FinchHTTPClientWithProxy_0,
        pools: %{
          default: [conn_opts: [proxy: {proxy.scheme, proxy.address, proxy.port, proxy.opts}]]
        }
      }
    ]
  end

  defp generate_finch_proxies(proxies) when is_list(proxies) do
    proxies
    |> Enum.with_index()
    |> Enum.map(fn {index, proxy} ->
      {
        Finch,
        name: :"FinchHTTPClientWithProxy_#{index}",
        pools: %{
          default: [conn_opts: [proxy: {proxy.scheme, proxy.address, proxy.port, proxy.opts}]]
        }
      }
    end)
  end
end
