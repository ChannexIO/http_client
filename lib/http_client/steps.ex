defmodule HTTPClient.Steps do
  @moduledoc """
  A collection of built-in steps.
  """

  require Logger

  alias HTTPClient.{Request, Response, Telemetry}

  @doc """
  Adds default steps.
  """
  def put_default_steps(request) do
    request
    |> Request.prepend_request_step(&__MODULE__.encode_headers/1)
    |> Request.prepend_request_step(&__MODULE__.put_default_headers/1)
    |> Request.prepend_request_step(&__MODULE__.encode_body/1)
    |> Request.prepend_request_step(&request.adapter.proxy/1)
    |> Request.prepend_request_step(&__MODULE__.auth/1)
    |> Request.prepend_request_step(&__MODULE__.put_params/1)
    |> Request.prepend_request_step(&__MODULE__.log_request_start/1)
    |> Request.prepend_adapter_step()
    |> Request.prepend_response_step(&__MODULE__.downcase_headers/1)
    |> Request.prepend_response_step(&__MODULE__.decompress_body/1)
    |> Request.prepend_response_step(&__MODULE__.decode_body/1)
    |> Request.prepend_response_step(&__MODULE__.retry/1)
    |> Request.prepend_response_step(&__MODULE__.log_response_end/1)
    |> Request.prepend_error_step(&__MODULE__.retry/1)
    |> Request.reverse_request_steps()
    |> Request.reverse_response_steps()
    |> Request.reverse_error_steps()
  end

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
  def auth(request) do
    auth(request, Map.get(request.options, :auth))
  end

  defp auth(request, nil), do: request

  defp auth(request, {:bearer, token}) when is_binary(token) do
    put_new_header(request, "authorization", "Bearer #{token}")
  end

  defp auth(request, {:basic, data}) when is_tuple(data) do
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
  Encodes the request body.

  ## Request Options

    * `:form` - if set, encodes the request body as form data (using `URI.encode_query/1`).

    * `:json` - if set, encodes the request body as JSON (using `Jason.encode_to_iodata!/1`), sets
                the `accept` header to `application/json`, and the `content-type`
                header to `application/json`.

  """
  def encode_body(%{body: {:form, data}} = request) do
    request
    |> Map.put(:body, URI.encode_query(data))
    |> put_new_header("content-type", "application/x-www-form-urlencoded")
  end

  def encode_body(%{body: {:json, data}} = request) do
    request
    |> Map.put(:body, Jason.encode_to_iodata!(data))
    |> put_new_header("content-type", "application/json")
    |> put_new_header("accept", "application/json")
  end

  def encode_body(request), do: request

  @doc """
  Adds params to request query string.
  """
  def put_params(request) do
    put_params(request, get_options(request.options, :params))
  end

  defp put_params(request, []) do
    request
  end

  defp put_params(request, params) do
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

  def decode_body({request, response}) when request.options.raw == true do
    {request, response}
  end

  def decode_body({request, response}) when request.options.decode_body == false do
    {request, response}
  end

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
  def decompress_body(request_response)

  def decompress_body({request, %{body: ""} = response}) do
    {request, response}
  end

  def decompress_body({request, response}) when request.options.raw == true do
    {request, response}
  end

  def decompress_body({request, response}) do
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

  @default_retry_delay :timer.seconds(2)

  @doc """
  Retries a request in face of errors.

  This function can be used as either or both response and error step.

  ## Request Options

    * `:retry` - can be one of the following:

        * `:safe` (default) - retry GET/HEAD requests on HTTP 408/429/5xx
          responses or exceptions

        * `:always` - always retry

    * `:condition_step` - step on the execution of which depends on whether
      to repeat the request

    * `:delay` - sleep this number of milliseconds before making another
      attempt, defaults to `#{@default_retry_delay}`. If the response is
      HTTP 429 and contains the `retry-after` header, the value of the header
      is used as the next retry delay.

    * `:max_retries` - maximum number of retry attempts, defaults to `2`
    (for a total of `3` requests to the server, including the initial one.)

  """
  def retry({request, exception}) when is_exception(exception) do
    retry(request, exception)
  end

  def retry({request, response})
      when not is_map_key(request.options, :retry) or request.options.retry == :safe do
    retry_safe(request, response)
  end

  def retry({request, response}) when request.options.retry == :always do
    retry(request, response)
  end

  def retry({request, response}) do
    default_condition = fn {_request, response} -> response.status >= 500 end
    condition_step = get_options(request.options.retry, :condition_step, default_condition)

    if Request.run_step(condition_step, {request, response}) do
      retry(request, response)
    else
      {request, response}
    end
  end

  defp retry_safe(request, response) do
    if request.method in [:get, :head] do
      case response do
        %Response{status: status} when status in [408, 429] or status in 500..599 ->
          retry(request, response)

        %Response{} ->
          {request, response}
      end
    else
      {request, response}
    end
  end

  defp retry(request, response_or_exception) do
    retry_count = Request.get_private(request, :retry_count, 0)

    case configure_retry(request, response_or_exception, retry_count) do
      %{retry?: true} = retry_params ->
        log_retry(response_or_exception, retry_count, retry_params)
        Process.sleep(retry_params.delay)
        request = Request.put_private(request, :retry_count, retry_count + 1)

        {_, result} = Request.run(request)
        {Request.halt(request), result}

      _ ->
        {request, response_or_exception}
    end
  end

  defp configure_retry(request, response_or_exception, retry_count) do
    retry_options = get_options(request.options, :retry)

    case get_retry_delay(retry_options, response_or_exception) do
      delay when is_integer(delay) ->
        max_retries = get_options(retry_options, :max_retries, 2)
        retry = retry_count < max_retries
        %{delay: delay, max_retries: max_retries, retry?: retry, type: :linear}

      {:retry_after, delay} ->
        %{delay: delay, retry?: true, type: :retry_after}

      :exponent ->
        max_cap = get_options(retry_options, :max_cap, :timer.minutes(20))
        delays = cap(exponential_backoff(), max_cap)
        %{delay: Enum.at(delays, retry_count), retry?: true, type: :exponent}

      :x_rate_limit ->
        delay = check_x_rate_limit(response_or_exception)
        %{delay: delay, retry?: true, type: :x_rate_limit}
    end
  end

  defp check_x_rate_limit(%Response{headers: headers}) do
    case get_headers(headers, ["x-ratelimit-reset", "x-ratelimit-remaining"]) do
      %{"x-ratelimit-remaining" => "0", "x-ratelimit-reset" => timestamp} ->
        get_x_rate_limit_delay(timestamp)

      %{"x-ratelimit-remaining" => "", "x-ratelimit-reset" => timestamp} ->
        get_x_rate_limit_delay(timestamp)

      %{"x-ratelimit-reset" => timestamp} = headers when map_size(headers) == 1 ->
        get_x_rate_limit_delay(timestamp)

      _headers ->
        @default_retry_delay
    end
  end

  defp check_x_rate_limit(_response_or_exception), do: @default_retry_delay

  defp get_x_rate_limit_delay(timestamp) do
    with {timestamp, ""} <- Integer.parse(timestamp),
         {:ok, datetime} <- DateTime.from_unix(timestamp),
         seconds when seconds > 0 <- DateTime.diff(datetime, DateTime.utc_now()) do
      :timer.seconds(seconds)
    else
      _ -> @default_retry_delay
    end
  end

  defp get_retry_delay(options, %Response{status: 429, headers: headers}) do
    case get_header(headers, "retry-after", 0) do
      {_, header_delay} -> {:retry_after, retry_delay_in_ms(header_delay)}
      0 -> {:retry_after, @default_retry_delay}
      nil -> get_options(options, :delay, @default_retry_delay)
    end
  end

  defp get_retry_delay(options, _response_or_exception) do
    get_options(options, :delay, @default_retry_delay)
  end

  defp exponential_backoff(initial_delay \\ :timer.seconds(1), factor \\ 2) do
    Stream.unfold(initial_delay, fn last_delay ->
      {last_delay, round(last_delay * factor)}
    end)
  end

  defp cap(delays, max) do
    Stream.map(delays, fn
      delay when delay <= max -> delay
      _ -> max
    end)
  end

  defp retry_delay_in_ms(delay_value) do
    case Integer.parse(delay_value) do
      {seconds, ""} ->
        :timer.seconds(seconds)

      :error ->
        delay_value
        |> parse_http_datetime()
        |> DateTime.diff(DateTime.utc_now(), :millisecond)
        |> max(0)
    end
  end

  defp log_retry(response_or_exception, retry_count, retry_params) do
    message =
      case retry_params do
        %{type: :retry_after} ->
          "Will retry after #{retry_params.delay}ms"

        %{type: :exponent} ->
          "Will retry in #{retry_params.delay}ms"

        %{type: :x_rate_limit} ->
          "Will retry after #{retry_params.delay}ms"

        %{max_retries: max_retries} when max_retries - retry_count == 1 ->
          "Will retry in #{retry_params.delay}ms, 1 attempt left"

        _retry_params ->
          attempts = retry_params.max_retries - retry_count
          "Will retry in #{retry_params.delay}ms, #{attempts} attempts left"
      end

    case response_or_exception do
      %{__exception__: true} = exception ->
        Logger.error(["retry: got exception. ", message])
        Logger.error(["** (#{inspect(exception.__struct__)}) ", Exception.message(exception)])

      response ->
        Logger.error(["retry: got response with status #{response.status}. ", message])
    end
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

  defp get_options(options, key, default \\ [])

  defp get_options(options, key, default) when is_map_key(options, key) do
    Map.get(options, key, default)
  end

  defp get_options(options, key, default), do: options[key] || default

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

  defp get_headers(headers, keys) when is_list(keys) do
    headers
    |> Keyword.take(keys)
    |> Map.new()
  end

  defp get_header(headers, name, default_value \\ nil) do
    Enum.find_value(headers, default_value, fn {key, value} ->
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

  @month_numbers %{
    "Jan" => "01",
    "Feb" => "02",
    "Mar" => "03",
    "Apr" => "04",
    "May" => "05",
    "Jun" => "06",
    "Jul" => "07",
    "Aug" => "08",
    "Sep" => "09",
    "Oct" => "10",
    "Nov" => "11",
    "Dec" => "12"
  }
  defp parse_http_datetime(datetime) do
    [_day_of_week, day, month, year, time, "GMT"] = String.split(datetime, " ")
    date = year <> "-" <> @month_numbers[month] <> "-" <> day

    case DateTime.from_iso8601(date <> " " <> time <> "Z") do
      {:ok, valid_datetime, 0} ->
        valid_datetime

      {:error, reason} ->
        raise "could not parse \"Retry-After\" header #{datetime} - #{reason}"
    end
  end
end
