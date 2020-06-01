defmodule HttpClientTest do
  use ExUnit.Case
  doctest HttpClient

  alias HttpClient.{Error, Response}

  setup do
    {:ok, bypass: Bypass.open()}
  end

  defmodule TestDefaultRequest do
    use HttpClient
  end

  defmodule TestFinchRequest do
    use HttpClient, adapter: :finch
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

      assert {ok, %Response{body: "OK", status: 200}} =
               TestFinchRequest.get(endpoint(bypass), headers, options)
    end

    test "get/3 error response", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, %Error{reason: :econnrefused}} ==
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
      options = [params: %{a: 1, b: 2}, basic_auth: {"username", "password"}]

      assert {ok, %Response{status: 200, body: ^response_body}} =
               TestFinchRequest.post(endpoint(bypass), req_body, headers, options)
    end

    test "post/4 error response", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, %Error{reason: :econnrefused}} ==
               TestFinchRequest.post(endpoint(bypass), "{}", [], [])
    end

    test "request/5 success response", %{bypass: bypass} do
      Bypass.expect_once(bypass, "DELETE", "/", fn conn ->
        Plug.Conn.send_resp(conn, 200, "OK")
      end)

      assert {ok, %Response{status: 200, body: "OK"}} =
               TestFinchRequest.request(:delete, endpoint(bypass), "", [], [])
    end

    test "request/5 error response", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, %Error{reason: :econnrefused}} ==
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
            assert meta.method == :get

            assert meta.options == [
                     hackney: [basic_auth: {"username", "password"}],
                     params: %{a: 1, b: 2},
                     basic_auth: {"username", "password"}
                   ]

            assert meta.url == endpoint(bypass)
            send(parent, {ref, :start})

          [:http_client, :request, :stop] ->
            assert is_integer(measurements.duration)
            assert meta.method == :get

            assert meta.options == [
                     hackney: [basic_auth: {"username", "password"}],
                     params: %{a: 1, b: 2},
                     basic_auth: {"username", "password"}
                   ]

            assert meta.url == endpoint(bypass)
            assert meta.status_code == 200
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
      options = [params: %{a: 1, b: 2}, basic_auth: {"username", "password"}]

      assert {:ok, %{status: 200}} = TestDefaultRequest.get(endpoint(bypass), headers, options)
      assert_receive {^ref, :start}
      assert_receive {^ref, :stop}

      :telemetry.detach(to_string(test_name))
    end
  end

  defp endpoint(%{port: port}, path \\ "/"), do: "http://localhost:#{port}#{path}"
end
