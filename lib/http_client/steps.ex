defmodule HTTPClient.Steps do
  @moduledoc """
  A collection of built-in steps.
  """

  require Logger

  alias HTTPClient.{Request, Telemetry}

  @doc """
  Adds default steps.

  ## Request steps

    * `encode_headers/1`

    * `put_default_headers/1`

    * `encode_body/1`

    * [`&auth(&1, options[:auth])`](`auth/2`) (if `options[:auth]` is set)

    * [`&put_params(&1, options[:params])`](`put_params/2`) (if `options[:params]` is set)

    * [`&run_steps(&1, options[:steps])`](`run_steps/2`) (if `options[:steps]` is set)

  ## Response steps

    * [`&retry(&1, options[:retry])`](`retry/2`) (if `options[:retry]` is set to
      an atom true or a options keywords list)

    * `decompress/1`

    * `decode_body/1`

  ## Options

    * `:auth` - if set, adds the `auth/2` step

    * `:params` - if set, adds the `put_params/2` step

    * `:raw` if set to `true`, skips `decompress/1` and `decode_body/1` steps

    * `:retry` - if set, adds the `retry/2` step to response step

    * `:steps` - if set, runs the `run_steps/2` step with the given steps

  """
  def put_default_steps(request, options \\ []) do
    request_steps =
      [
        {__MODULE__, :encode_headers, []},
        {__MODULE__, :put_default_headers, []},
        {__MODULE__, :encode_body, []},
        {request.adapter, :proxy, []}
      ] ++
        maybe_steps(options[:auth], [{__MODULE__, :auth, [options[:auth]]}]) ++
        maybe_steps(options[:params], [{__MODULE__, :put_params, [options[:params]]}]) ++
        maybe_steps(options[:steps], [{__MODULE__, :run_steps, [options[:steps]]}])

    request_telemetry_step = {__MODULE__, :log_request_start, []}
    response_telemetry_step = {__MODULE__, :log_response_end, []}

    retry = options[:retry]
    retry = if retry == true, do: [], else: retry

    raw? = if is_nil(options[:raw]), do: true, else: options[:raw] == true

    response_steps =
      [{__MODULE__, :downcase_headers, []}] ++
        maybe_steps(not raw?, [
          {__MODULE__, :decompress, []},
          {__MODULE__, :decode_body, []}
        ]) ++
        maybe_steps(retry, [{__MODULE__, :retry, [retry]}])

    request
    |> Request.append_request_steps(request_steps)
    |> Request.append_request_steps([request_telemetry_step])
    |> Request.append_adapter_step()
    |> Request.append_response_steps(response_steps)
    |> Request.append_response_steps([response_telemetry_step])
  end

  defp maybe_steps(nil, _step), do: []
  defp maybe_steps(false, _step), do: []
  defp maybe_steps(_, steps), do: steps

  @doc """
  Adds common request headers.

  Currently the following headers are added:

    * `"accept-encoding"` - `"gzip"`

  """
  def put_default_headers(request) do
    put_new_header(request, "accept-encoding", "gzip")
  end

  @doc """
  Sets request authentication.

  `auth` can be one of:

    * `{:basic, tuple}` - uses Basic HTTP authentication
    * `{:bearer, token}` - uses Bearer HTTP authentication
  """
  def auth(request, {:bearer, token}) when is_binary(token) do
    put_new_header(request, "authorization", "Bearer #{token}")
  end

  def auth(request, {:basic, data}) when is_tuple(data) do
    0
    |> Range.new(tuple_size(data) - 1)
    |> Enum.map_join(":", &"#{elem(data, &1)}")
    |> Base.encode64()
    |> then(&put_new_header(request, "authorization", "Basic #{&1}"))
  end

  @doc """
  Encodes request headers.

  Turns atom header names into strings, replacing `-` with `_`. For example, `:user_agent` becomes
  `"user-agent"`. Non-atom header names are kept as is.

  If a header value is a `NaiveDateTime` or `DateTime`, it is encoded as "HTTP date". Otherwise,
  the header value is encoded with `String.Chars.to_string/1`.
  """
  def encode_headers(request) do
    headers =
      for {name, value} <- request.headers do
        {prepare_header_name(name), prepare_header_value(value)}
      end

    %{request | headers: headers}
  end

  @doc """
  Encodes the request body based on its shape.

  If body is of the following shape, it's encoded and its `content-type` set
  accordingly. Otherwise it's unchanged.

  | Shape           | Encoder                     | Content-Type                          |
  | --------------- | --------------------------- | ------------------------------------- |
  | `{:form, data}` | `URI.encode_query/1`        | `"application/x-www-form-urlencoded"` |
  | `{:json, data}` | `Jason.encode_to_iodata!/1` | `"application/json"`                  |

  """
  def encode_body(request) do
    case request.body do
      {:form, data} ->
        request
        |> Map.put(:body, URI.encode_query(data))
        |> put_new_header("content-type", "application/x-www-form-urlencoded")

      {:json, data} ->
        request
        |> Map.put(:body, Jason.encode_to_iodata!(data))
        |> put_new_header("content-type", "application/json")

      _other ->
        request
    end
  end

  @doc """
  Adds params to request query string.
  """
  def put_params(request, params) do
    encoded = URI.encode_query(params)

    update_in(request.url.query, fn
      nil -> encoded
      query -> query <> "&" <> encoded
    end)
  end

  @doc false
  def log_request_start(request) do
    metadata = %{
      adapter: request.adapter,
      headers: request.headers,
      method: request.method,
      url: to_string(request.url)
    }

    start_time = Telemetry.start(:request, metadata)
    update_in(request.private, &Map.put(&1, :request_start_time, start_time))
  end

  @doc """
  Decodes response body based on the detected format.

  Supported formats:

  | Format | Decoder                                                          |
  | ------ | ---------------------------------------------------------------- |
  | json   | `Jason.decode!/1`                                                |
  | gzip   | `:zlib.gunzip/1`                                                 |

  """
  def decode_body({request, %{body: ""} = response}), do: {request, response}

  def decode_body({request, response}) do
    case format(request, response) do
      "json" ->
        {request, update_in(response.body, &Jason.decode!/1)}

      "gz" ->
        {request, update_in(response.body, &:zlib.gunzip/1)}

      _ ->
        {request, response}
    end
  end

  defp format(_request, response) do
    with {_, content_type} <- List.keyfind(response.headers, "content-type", 0) do
      case MIME.extensions(content_type) do
        [ext | _] -> ext
        [] -> nil
      end
    end
  end

  @doc """
  Downcase response headers names.
  """
  def downcase_headers({request, response}) when is_exception(response) do
    {request, response}
  end

  def downcase_headers({request, response}) do
    headers = for {name, value} <- response.headers, do: {prepare_header_name(name), value}
    {request, %{response | headers: headers}}
  end

  @doc """
  Decompresses the response body based on the `content-encoding` header.
  """
  def decompress(request_response)

  def decompress({request, %{body: ""} = response}) do
    {request, response}
  end

  def decompress({request, response}) do
    compression_algorithms = get_content_encoding_header(response.headers)
    {request, update_in(response.body, &decompress_body(&1, compression_algorithms))}
  end

  defp decompress_body(body, algorithms) do
    Enum.reduce(algorithms, body, &decompress_with_algorithm(&1, &2))
  end

  defp decompress_with_algorithm(gzip, body) when gzip in ["gzip", "x-gzip"] do
    :zlib.gunzip(body)
  end

  defp decompress_with_algorithm("deflate", body) do
    :zlib.unzip(body)
  end

  defp decompress_with_algorithm("identity", body) do
    body
  end

  defp decompress_with_algorithm(algorithm, _body) do
    raise("unsupported decompression algorithm: #{inspect(algorithm)}")
  end

  @doc """
  Retries a request in face of errors.

  It retries a request that resulted in:

    * a response with status 5xx

    * an exception

  ## Options

    * `:condition_step` - step on the execution of which depends on whether
      to repeat the request

    * `:delay` - sleep this number of milliseconds before making another
      attempt, defaults to `2000`

    * `:max_retries` - maximum number of retry attempts, defaults to `2`
      (for a total of `3` requests to the server, including the initial one.)

  """
  def retry({request, exception}, options) when is_exception(exception) and is_list(options) do
    retry(request, exception, options)
  end

  def retry({request, response}, options) when is_list(options) do
    default_condition = fn {_request, response} -> response.status >= 500 end
    condition_step = Keyword.get(options, :condition_step, default_condition)

    if Request.run_step(condition_step, {request, response}) do
      retry(request, response, options)
    else
      {request, response}
    end
  end

  defp retry(request, response_or_exception, options) do
    delay = Keyword.get(options, :delay, 2000)
    max_retries = Keyword.get(options, :max_retries, 2)
    retry_count = Request.get_private(request, :retry_count, 0)

    if retry_count < max_retries do
      log_retry(response_or_exception, retry_count, max_retries, delay)
      Process.sleep(delay)
      request = Request.put_private(request, :retry_count, retry_count + 1)

      {_, result} = Request.run(request)
      {Request.halt(request), result}
    else
      {request, response_or_exception}
    end
  end

  defp log_retry(response_or_exception, retry_count, max_retries, delay) do
    retries_left =
      case max_retries - retry_count do
        1 -> "1 attempt"
        n -> "#{n} attempts"
      end

    message = ["Will retry in #{delay}ms, ", retries_left, " left"]

    case response_or_exception do
      %{__exception__: true} = exception ->
        Logger.error(["HTTPClient: Got exception. ", message])
        Logger.error(["** (#{inspect(exception.__struct__)}) ", Exception.message(exception)])

      response ->
        Logger.error(["HTTPClient: Got response with status #{response.status}. ", message])
    end
  end

  @doc """
  Runs the given steps.

  A step is a function that takes and returns a usually updated `state`.
  The `state` is:

    * a `request` struct for request steps

    * a `{request, response}` tuple for response steps

    * a `{request, exception}` tuple for error steps

  A step can be one of the following:

    * a 1-arity function

    * a `{module, function, args}` tuple - calls `apply(module, function, [state | args])`

    * a `{module, options}` tuple - calls `module.run(state, options)`

    * a `module` atom - calls `module.run(state, [])`

  """
  def run_steps(request, steps) when is_list(steps) do
    Enum.reduce(steps, request, &Request.run_step/2)
  end

  @doc false
  def log_response_end({request, response_or_exception}) do
    start_time = request.private.request_start_time
    metadata = %{adapter: request.adapter, method: request.method, url: to_string(request.url)}
    Telemetry.stop(:request, start_time, enrich_metadata(metadata, response_or_exception))
    {request, response_or_exception}
  end

  defp enrich_metadata(metadata, exception) when is_exception(exception) do
    Map.put(metadata, :error, Exception.message(exception))
  end

  defp enrich_metadata(metadata, response) do
    metadata
    |> Map.put(:headers, response.headers)
    |> Map.put(:status_code, response.status)
  end

  ## Utilities

  defp get_content_encoding_header(headers) do
    if value = get_header(headers, "content-encoding") do
      value
      |> String.downcase()
      |> String.split(",", trim: true)
      |> Stream.map(&String.trim/1)
      |> Enum.reverse()
    else
      []
    end
  end

  defp get_header(headers, name) do
    Enum.find_value(headers, nil, fn {key, value} ->
      if String.downcase(key) == name, do: value
    end)
  end

  defp put_new_header(struct, name, value) do
    if Enum.any?(struct.headers, fn {key, _} -> String.downcase(key) == name end) do
      struct
    else
      put_header(struct, name, value)
    end
  end

  defp put_header(struct, name, value) do
    update_in(struct.headers, &[{name, value} | &1])
  end

  defp prepare_header_name(name) when is_atom(name) do
    name
    |> Atom.to_string()
    |> String.replace("_", "-")
    |> String.downcase()
  end

  defp prepare_header_name(name) when is_binary(name), do: String.downcase(name)

  defp prepare_header_value(%NaiveDateTime{} = naive_datetime), do: naive_datetime

  defp prepare_header_value(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> format_http_datetime()
  end

  defp prepare_header_value(value), do: String.Chars.to_string(value)

  defp format_http_datetime(datetime) do
    Calendar.strftime(datetime, "%a, %d %b %Y %H:%M:%S GMT")
  end
end
