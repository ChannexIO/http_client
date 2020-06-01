defmodule HttpClient.Telemetry do
  @moduledoc """
  Telemetry integration.

  Unless specified, all time's are in `:native` units.

  HttpClient executes the following events:

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
  """

  @doc false
  # emits a `start` telemetry event and returns the the start time
  def start(event, meta \\ %{}, extra_measurements \\ %{}) do
    start_time = System.monotonic_time()
    measurements = Map.merge(extra_measurements, %{system_time: System.system_time()})
    event([event, :start], measurements, meta)
    start_time
  end

  @doc false
  # Emits a stop event.
  def stop(event, start_time, meta \\ %{}, extra_measurements \\ %{}) do
    end_time = System.monotonic_time()
    measurements = Map.merge(extra_measurements, %{duration: end_time - start_time})
    event([event, :stop], measurements, meta)
  end

  @doc false
  # Used for reporting generic events
  def event(event, measurements, meta) do
    :telemetry.execute([:http_client | event], measurements, meta)
  end
end
