defmodule HTTPClientTest do
  use ExUnit.Case, async: true

  doctest HTTPClient

  alias HTTPClient.{Error, Response}

  setup do
    {:ok, ambush: Ambush.open()}
  end

  defmodule TestDefaultRequest do
    use HTTPClient
  end

  defmodule TestFinchRequest do
    use HTTPClient, adapter: :finch
  end

  describe "Finch HTTP Client" do
    test "get/3 success response", %{ambush: ambush} do
      Ambush.expect_once(ambush, "GET", "/", fn conn ->
        assert conn.query_string == "a=1"
        assert {_, "text/xml"} = Enum.find(conn.req_headers, &(elem(&1, 0) == "content-type"))

        Plug.Conn.send_resp(conn, 200, "OK")
      end)

      headers = [{"Content-Type", "text/xml"}]
      options = [params: %{a: 1}]

      assert {:ok, %Response{body: "OK", status: 200}} =
               TestFinchRequest.get(endpoint(ambush), headers, options)
    end

    @tag :skip
    test "get/3 error response", %{ambush: ambush} do
      # Ambush.down(ambush)

      assert {:error, %Error{reason: "connection refused"}} ==
               TestFinchRequest.get(endpoint(ambush), [], [])
    end

    test "post/4 success response", %{ambush: ambush} do
      req_body = ~s({"response":"please"})
      response_body = ~s({"right":"here"})

      Ambush.expect_once(ambush, "POST", "/", fn conn ->
        assert %{"a" => "1", "b" => "2"} == URI.decode_query(conn.query_string)

        assert {_, "application/json"} =
                 Enum.find(conn.req_headers, &(elem(&1, 0) == "content-type"))

        assert {_, "Basic dXNlcm5hbWU6cGFzc3dvcmQ="} =
                 Enum.find(conn.req_headers, &(elem(&1, 0) == "authorization"))

        assert {:ok, ^req_body, conn} = Plug.Conn.read_body(conn)

        Plug.Conn.send_resp(conn, 200, response_body)
      end)

      headers = [{"content-type", "application/json"}]
      options = [params: %{a: 1, b: 2}, auth: {:basic, {"username", "password"}}]

      assert {:ok, %Response{status: 200, body: ^response_body}} =
               TestFinchRequest.post(endpoint(ambush), req_body, headers, options)
    end

    @tag :skip
    test "post/4 error response", %{ambush: ambush} do
      # Ambush.down(ambush)

      assert {:error, %Error{reason: "connection refused"}} ==
               TestFinchRequest.post(endpoint(ambush), "{}", [], [])
    end

    test "request/5 success response", %{ambush: ambush} do
      Ambush.expect_once(ambush, "DELETE", "/", fn conn ->
        Plug.Conn.send_resp(conn, 200, "OK")
      end)

      assert {:ok, %Response{status: 200, body: "OK"}} =
               TestFinchRequest.request(:delete, endpoint(ambush), "", [], [])
    end

    @tag :skip
    test "request/5 error response", %{ambush: ambush} do
      # Ambush.down(ambush)

      assert {:error, %Error{reason: "connection refused"}} ==
               TestFinchRequest.request(:post, endpoint(ambush), "{}", [], [])
    end
  end

  describe "telemetry" do
    setup %{ambush: ambush} do
      Ambush.expect_once(ambush, "GET", "/", fn conn ->
        Plug.Conn.send_resp(conn, 200, "OK")
      end)

      :ok
    end

    test "reports request events", %{ambush: ambush} do
      {test_name, _arity} = __ENV__.function

      parent = self()
      ref = make_ref()

      handler = fn event, measurements, meta, _config ->
        case event do
          [:http_client, :request, :start] ->
            assert is_integer(measurements.system_time)
            assert meta.adapter == HTTPClient.Adapters.HTTPoison

            assert meta.headers == [
                     {"authorization", "Basic dXNlcm5hbWU6cGFzc3dvcmQ="},
                     {"accept-encoding", "gzip"},
                     {"content-type", "application/json"}
                   ]

            assert meta.method == :get
            assert_same_url(meta.url, endpoint(ambush, "/?a=1&b=2"))
            send(parent, {ref, :start})

          [:http_client, :request, :stop] ->
            assert is_integer(measurements.duration)
            assert meta.adapter == HTTPClient.Adapters.HTTPoison
            assert is_list(meta.headers)
            assert meta.method == :get
            assert meta.status_code == 200
            assert_same_url(meta.url, endpoint(ambush, "/?a=1&b=2"))
            send(parent, {ref, :stop})

          _ ->
            flunk("Unknown event")
        end
      end

      :telemetry.attach_many(
        to_string(test_name),
        [
          [:http_client, :request, :start],
          [:http_client, :request, :stop]
        ],
        handler,
        nil
      )

      headers = [{"content-type", "application/json"}]
      options = [params: %{a: 1, b: 2}, auth: {:basic, {"username", "password"}}]

      assert {:ok, %{status: 200}} = TestDefaultRequest.get(endpoint(ambush), headers, options)
      assert_receive {^ref, :start}
      assert_receive {^ref, :stop}

      :telemetry.detach(to_string(test_name))
    end
  end

  describe "response" do
    test "same for all adapters", %{ambush: ambush} do
      Ambush.expect(ambush, "POST", "/", fn conn ->
        Plug.Conn.send_resp(conn, 200, "OK")
      end)

      headers = [{"content-type", "application/json"}]
      options = [params: %{a: 1, b: 2}]
      url = endpoint(ambush)

      assert {:ok, finch_response} = TestFinchRequest.post(url, "{}", headers, options)
      assert {:ok, default_response} = TestDefaultRequest.post(url, "{}", headers, options)
      assert finch_response == default_response

      assert %Response{
               body: "OK",
               headers: _headers,
               request_url: request_url,
               status: 200
             } = default_response

      assert %{query: query} = URI.parse(request_url)
      assert %{"a" => "1", "b" => "2"} == URI.decode_query(query)
    end
  end

  describe "retry with Retry-After" do
    @describetag timeout: 10_000

    test "stops after max_retries", %{ambush: ambush} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Ambush.expect(ambush, "GET", "/", fn conn ->
        Agent.update(counter, &(&1 + 1))

        conn
        |> Plug.Conn.put_resp_header("retry-after", "0")
        |> Plug.Conn.send_resp(429, "slow down")
      end)

      options = [retry: [condition_step: &rate_limited?/1, max_retries: 2]]

      assert {:ok, %Response{status: 429}} = TestFinchRequest.get(endpoint(ambush), [], options)
      assert Agent.get(counter, & &1) == 3
    end

    test "caps the Retry-After delay at max_cap", %{ambush: ambush} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Ambush.expect(ambush, "GET", "/", fn conn ->
        Agent.update(counter, &(&1 + 1))

        conn
        |> Plug.Conn.put_resp_header("retry-after", "5")
        |> Plug.Conn.send_resp(429, "slow down")
      end)

      options = [retry: [condition_step: &rate_limited?/1, max_retries: 1, max_cap: 10]]
      started_at = System.monotonic_time(:millisecond)

      assert {:ok, %Response{status: 429}} = TestFinchRequest.get(endpoint(ambush), [], options)
      assert Agent.get(counter, & &1) == 2
      assert System.monotonic_time(:millisecond) - started_at < 1_000
    end
  end

  defp rate_limited?({_request, %Response{status: status}}), do: status == 429
  defp rate_limited?(_request_response), do: false

  defp endpoint(%{port: port}, path \\ "/"), do: "http://localhost:#{port}#{path}"

  defp assert_same_url(actual, expected) do
    actual_uri = URI.new!(actual)
    expected_uri = URI.new!(expected)

    assert %{actual_uri | query: nil} == %{expected_uri | query: nil}
    assert URI.decode_query(actual_uri.query || "") == URI.decode_query(expected_uri.query || "")
  end
end
