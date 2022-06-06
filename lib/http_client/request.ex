defmodule HTTPClient.Request do
  @moduledoc """
  The request struct.

  Struct fields:

  * `:adapter` - an implementation of adapter to use

  * `:options` - steps and adapter options

  * `:method` - the HTTP request method

  * `:url` - the HTTP request URL

  * `:headers` - the HTTP request headers

  * `:body` - the HTTP request body

  * `:halted` - whether the request pipeline is halted. See `halt/1`

  * `:request_steps` - the list of request steps

  * `:response_steps` - the list of response steps

  * `:error_steps` - the list of error steps

  * `:private` - a map reserved for internal use.

  """

  alias HTTPClient.{Error, Request, Response}

  defstruct [
    :adapter,
    method: :get,
    url: "",
    options: [],
    headers: [],
    body: "",
    halted: false,
    request_steps: [],
    response_steps: [],
    error_steps: [],
    private: %{}
  ]

  @doc """
  Gets the value for a specific private `key`.
  """
  def get_private(request, key, default \\ nil) when is_atom(key) do
    Map.get(request.private, key, default)
  end

  @doc """
  Assigns a private `key` to `value`.
  """
  def put_private(request, key, value) when is_atom(key) do
    put_in(request.private[key], value)
  end

  @doc """
  Halts the request preventing any further steps from executing.
  """
  def halt(request) do
    %{request | halted: true}
  end

  @doc """
  Builds a request.
  """
  def build(adapter, method, url, options \\ []) do
    %__MODULE__{
      adapter: adapter,
      options: prepare_options(options),
      method: method,
      url: URI.parse(url),
      headers: Keyword.get(options, :headers, []),
      body: Keyword.get(options, :body, "")
    }
  end

  @doc """
  Prepends adapter step to request steps.
  """
  def prepend_adapter_step(request) do
    prepend_request_step(request, &request.adapter.perform_request/1)
  end

  @doc """
  Prepends request step.
  """
  def prepend_request_step(request, step) do
    update_in(request.request_steps, &[step | &1])
  end

  @doc """
  Reverses request steps.
  """
  def reverse_request_steps(request) do
    update_in(request.request_steps, &Enum.reverse/1)
  end

  @doc """
  Prepends response step.
  """
  def prepend_response_step(request, step) do
    update_in(request.response_steps, &[step | &1])
  end

  @doc """
  Reverses response steps.
  """
  def reverse_response_steps(request) do
    update_in(request.response_steps, &Enum.reverse/1)
  end

  @doc """
  Prepends error step.
  """
  def prepend_error_step(request, step) do
    update_in(request.error_steps, &[step | &1])
  end

  @doc """
  Reverses error steps.
  """
  def reverse_error_steps(request) do
    update_in(request.error_steps, &Enum.reverse/1)
  end

  @doc """
  Runs a request pipeline.

  Returns `{:ok, response}` or `{:error, exception}`.
  """
  def run(request) do
    run_request(request.request_steps, request)
  end

  defp run_request([step | steps], request) do
    case run_step(step, request) do
      %Request{} = request ->
        run_request(steps, request)

      {%Request{halted: true}, response_or_exception} ->
        result(response_or_exception)

      {request, %Response{} = response} ->
        run_response(request, response)

      {request, exception} when is_exception(exception) ->
        run_error(request, exception)
    end
  end

  defp run_request([], request) do
    case run_step(&request.adapter.perform_request/1, request) do
      {request, %Response{} = response} ->
        run_response(request, response)

      {request, exception} when is_exception(exception) ->
        run_error(request, exception)

      other ->
        raise "expected adapter to return {request, response} or {request, exception}, " <>
                "got: #{inspect(other)}"
    end
  end

  defp run_response(request, response) do
    steps = request.response_steps

    {_request, response_or_exception} =
      Enum.reduce_while(steps, {request, response}, fn step, {request, response} ->
        case run_step(step, {request, response}) do
          {%Request{halted: true} = request, response_or_exception} ->
            {:halt, {request, response_or_exception}}

          {request, %Response{} = response} ->
            {:cont, {request, response}}

          {request, exception} when is_exception(exception) ->
            {:halt, run_error(request, exception)}
        end
      end)

    result(response_or_exception)
  end

  defp run_error(request, exception) do
    steps = request.error_steps

    {_request, response_or_exception} =
      Enum.reduce_while(steps, {request, exception}, fn step, {request, exception} ->
        case run_step(step, {request, exception}) do
          {%Request{halted: true} = request, response_or_exception} ->
            {:halt, {request, response_or_exception}}

          {request, exception} when is_exception(exception) ->
            {:cont, {request, exception}}

          {request, %Response{} = response} ->
            {:halt, run_response(request, response)}
        end
      end)

    result(response_or_exception)
  end

  @doc false
  def run_step(step, state)

  def run_step({module, function, args}, state) do
    apply(module, function, [state | args])
  end

  def run_step({module, options}, state) do
    apply(module, :run, [state | [options]])
  end

  def run_step(module, state) when is_atom(module) do
    apply(module, :run, [state, []])
  end

  def run_step(func, state) when is_function(func, 1) do
    func.(state)
  end

  defp result(%Response{} = response) do
    {:ok, response}
  end

  defp result(exception) when is_exception(exception) do
    {:error, %Error{reason: Exception.message(exception)}}
  end

  defp prepare_options(options) do
    options
    |> Keyword.get(:options, [])
    |> Map.new()
  end
end
