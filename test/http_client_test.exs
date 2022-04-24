defmodule HTTPClientTest do
  use ExUnit.Case
  doctest HTTPClient

  alias HTTPClient.{Error, Response}

  setup do
    {:ok, bypass: Bypass.open()}
  end

  defmodule TestDefaultRequest do
    use HTTPClient
  end

  defmodule TestFinchRequest do
    use HTTPClient, adapter: :finch
  end

  describe "Finch HTTP Client" do
    test "get/3 success response", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/", fn conn ->
        assert conn.query_string == "a=1"
        assert {_, "text/xml"} = Enum.find(conn.req_headers, &(elem(&1, 0) == "content-type"))

        Plug.Conn.send_resp(conn, 200, "OK")
      end)

      headers = [{"Content-Type", "text/xml"}]
      options = [params: %{a: 1}]

      assert {:ok, %Response{body: "OK", status: 200}} =
               TestFinchRequest.get(endpoint(bypass), headers, options)
    end

    test "get/3 error response", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, %Error{reason: "connection refused"}} ==
               TestFinchRequest.get(endpoint(bypass), [], [])
    end

    test "post/4 success response", %{bypass: bypass} do
      req_body = ~s({"response":"please"})
      response_body = ~s({"right":"here"})

      Bypass.expect_once(bypass, "POST", "/", fn conn ->
        assert conn.query_string == "a=1&b=2"

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
               TestFinchRequest.post(endpoint(bypass), req_body, headers, options)
    end

    test "post/4 error response", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, %Error{reason: "connection refused"}} ==
               TestFinchRequest.post(endpoint(bypass), "{}", [], [])
    end

    test "request/5 success response", %{bypass: bypass} do
      Bypass.expect_once(bypass, "DELETE", "/", fn conn ->
        Plug.Conn.send_resp(conn, 200, "OK")
      end)

      assert {:ok, %Response{status: 200, body: "OK"}} =
               TestFinchRequest.request(:delete, endpoint(bypass), "", [], [])
    end

    test "request/5 error response", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, %Error{reason: "connection refused"}} ==
               TestFinchRequest.request(:post, endpoint(bypass), "{}", [], [])
    end
  end

  describe "telemetry" do
    setup %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/", fn conn ->
        Plug.Conn.send_resp(conn, 200, "OK")
      end)

      :ok
    end

    test "reports request events", %{bypass: bypass} do
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
            assert meta.url == endpoint(bypass) <> "?a=1&b=2"
            send(parent, {ref, :start})

          [:http_client, :request, :stop] ->
            assert is_integer(measurements.duration)
            assert meta.adapter == HTTPClient.Adapters.HTTPoison
            assert is_list(meta.headers)
            assert meta.method == :get
            assert meta.status_code == 200
            assert meta.url == endpoint(bypass) <> "?a=1&b=2"
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

      assert {:ok, %{status: 200}} = TestDefaultRequest.get(endpoint(bypass), headers, options)
      assert_receive {^ref, :start}
      assert_receive {^ref, :stop}

      :telemetry.detach(to_string(test_name))
    end
  end

  describe "response" do
    test "same for all adapters", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/", fn conn ->
        Plug.Conn.send_resp(conn, 200, "OK")
      end)

      headers = [{"content-type", "application/json"}]
      options = [params: %{a: 1, b: 2}]
      url = endpoint(bypass)

      assert {:ok, finch_response} = TestFinchRequest.post(url, "{}", headers, options)
      assert {:ok, default_response} = TestDefaultRequest.post(url, "{}", headers, options)
      assert finch_response == default_response

      assert %Response{
               body: "OK",
               headers: _headers,
               request_url: request_url,
               status: 200
             } = default_response

      assert to_string(request_url) == url <> "?a=1&b=2"
    end
  end

  defp endpoint(%{port: port}, path \\ "/"), do: "http://localhost:#{port}#{path}"
end
