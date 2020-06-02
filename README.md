<!-- MDOC !-->

# HTTPClient

Facade for HTTP client.

This module is meant to be `use`'d in custom modules in order to wrap the functionalities 
provided by supported HTTP clients.

## Usage

For example, to build API clients around HTTClient:

```elixir
defmodule GitHub do
  use HTTClient
  
  @endpoint "https://api.github.com"
    
  def read_repo(url, headers, option) do
    get(@endpoint <> url, headers, option)
  end
end
```

This way, all requests done through the `GitHub` module will be done to the GitHub API:
    
    GitHub.read_repo("/repos/ChannexIO/http_client", headers, options)
    #=> will issue a GET request at https://api.github.com/repos/ChannexIO/http_client

By default requests done through HTTPoison client, to use Finch, for example, 
add `use` options:
    
    use HTTClient, adapter: :finch

## Telemetry

HTTPClient uses Telemetry to provide the following events:

  * `[:http_client, :request, :start]` - Executed before sending a request.

    #### Measurements:
    * `:system_time` - The system time

    #### Metadata:
    * `:method` - The method used in the request.
    * `:url` - The url address.
    * `:options` - The request options.

  * `[:http_client, :request, :stop]` - Executed after a request is finished.

    #### Measurements:
    * `:duration` - Duration to make the request.

    #### Metadata:
    * `:method` - The method used in the request.
    * `:url` - The url address.
    * `:options` - The request options.
    * `:status_code` - This value is optional. The response status code.
    * `:error` - This value is optional. It includes any errors that occured while making the request.

See the `HTTClient.Telemetry` module for details on specific events.

<!-- MDOC !-->

## Installation

Can be installed by adding `http_client` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:http_client, github: "ChannexIO/http_client"}
  ]
end
```
