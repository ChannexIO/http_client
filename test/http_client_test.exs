defmodule HTTPClientTest do
  use ExUnit.Case, async: true

  doctest HTTPClient

  alias HTTPClient.Response

  setup do
    {:ok, lasso: Lasso.open()}
  end

  defmodule TestDefaultRequest do
    use HTTPClient
  end

  defmodule TestFinchRequest do
    use HTTPClient, adapter: :finch
  end

  describe "Finch HTTP Client" do
    test "get/3 success response", %{lasso: lasso} do
      Lasso.expect_once(lasso, "GET", "/", fn conn ->
        assert conn.query_string == "a=1"
        assert {_, "text/xml"} = Enum.find(conn.req_headers, &(elem(&1, 0) == "content-type"))

        Plug.Conn.send_resp(conn, 200, "OK")
      end)

      headers = [{"Content-Type", "text/xml"}]
      options = [params: %{a: 1}]

      assert {:ok, %Response{body: "OK", status: 200}} =
               TestFinchRequest.get(endpoint(lasso), headers, options)
    end

    test "post/4 success response", %{lasso: lasso} do
      req_body = ~s({"response":"please"})
      response_body = ~s({"right":"here"})

      Lasso.expect_once(lasso, "POST", "/", fn conn ->
        assert %{"a" => "1", "b" => "2"} == URI.decode_query(conn.query_string)

        assert {_, "application/json"} =
                 Enum.find(conn.req_headers, &(elem(&1, 0) == "content-type"))

        assert {_, "Basic dXNlcm5hbWU6cGFzc3dvcmQ="} =
                 Enum.find(conn.req_headers, &(elem(&1, 0) == "authorization"))

        assert {:ok, ^req_body, conn} = Plug.Conn.read_body(conn)

        Plug.Conn.send_resp(conn, 200, response_body)
      end)

      headers = [{"content-type", "application/json"}]
      options = [params: %{a: 1, b: 2}, basic_auth: {"username", "password"}]

      assert {:ok, %Response{status: 200, body: ^response_body}} =
               TestFinchRequest.post(endpoint(lasso), req_body, headers, options)
    end

    test "request/5 success response", %{lasso: lasso} do
      Lasso.expect_once(lasso, "DELETE", "/", fn conn ->
        Plug.Conn.send_resp(conn, 200, "OK")
      end)

      assert {:ok, %Response{status: 200, body: "OK"}} =
               TestFinchRequest.request(:delete, endpoint(lasso), "", [], [])
    end
  end

  describe "telemetry" do
    setup %{lasso: lasso} do
      Lasso.expect_once(lasso, "GET", "/", fn conn ->
        Plug.Conn.send_resp(conn, 200, "OK")
      end)

      :ok
    end

    test "reports request events", %{lasso: lasso} do
      {test_name, _arity} = __ENV__.function

      parent = self()
      ref = make_ref()

      handler = fn event, measurements, meta, _config ->
        case event do
          [:http_client, :request, :start] ->
            assert is_integer(measurements.system_time)
            assert meta.adapter == HTTPClient.Adapters.HTTPoison

            assert meta.args == [
                     endpoint(lasso),
                     [{"content-type", "application/json"}],
                     [params: %{a: 1, b: 2}, basic_auth: {"username", "password"}]
                   ]

            assert meta.method == :get
            send(parent, {ref, :start})

          [:http_client, :request, :stop] ->
            assert is_integer(measurements.duration)
            assert meta.adapter == HTTPClient.Adapters.HTTPoison

            assert meta.args == [
                     endpoint(lasso),
                     [{"content-type", "application/json"}],
                     [params: %{a: 1, b: 2}, basic_auth: {"username", "password"}]
                   ]

            assert meta.method == :get
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

      assert {:ok, %{status: 200}} = TestDefaultRequest.get(endpoint(lasso), headers, options)
      assert_receive {^ref, :start}
      assert_receive {^ref, :stop}

      :telemetry.detach(to_string(test_name))
    end
  end

  describe "response" do
    test "same for all adapters", %{lasso: lasso} do
      Lasso.expect(lasso, "POST", "/", fn conn ->
        Plug.Conn.send_resp(conn, 200, "OK")
      end)

      headers = [{"content-type", "application/json"}]
      options = [params: %{a: 1, b: 2}]
      url = endpoint(lasso)

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

  defp endpoint(%{port: port}, path \\ "/"), do: "http://localhost:#{port}#{path}"
end
