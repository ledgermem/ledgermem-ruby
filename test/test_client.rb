# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "socket"
require "ledgermem"

# Tiny one-shot HTTP mock — no external deps.
class MockServer
  attr_reader :port, :requests

  def initialize(handler)
    @handler = handler
    @requests = []
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @thread = Thread.new { loop { handle_one } }
  end

  def stop
    @thread.kill
    @server.close
  end

  private

  def handle_one
    socket = @server.accept
    request_line = socket.gets
    return socket.close unless request_line

    method, path, _ = request_line.split(" ")
    headers = {}
    while (line = socket.gets) && line != "\r\n"
      k, v = line.chomp.split(": ", 2)
      headers[k] = v if k
    end
    body = ""
    if (len = headers["Content-Length"]&.to_i) && len.positive?
      body = socket.read(len)
    end
    @requests << {
      method: method,
      path: path,
      auth: headers["Authorization"],
      workspace: headers["x-workspace-id"],
      body: body.empty? ? nil : JSON.parse(body)
    }
    status, response_body = @handler.call(method, path)
    socket.write("HTTP/1.1 #{status} OK\r\n")
    socket.write("Content-Type: application/json\r\n")
    socket.write("Content-Length: #{response_body.bytesize}\r\n")
    socket.write("Connection: close\r\n\r\n")
    socket.write(response_body)
  rescue StandardError
    # swallow — test will fail on assertion
  ensure
    socket&.close
  end
end

class ClientTest < Minitest::Test
  def setup
    handler = lambda do |_method, path|
      case path
      when "/v1/memories"
        [201, JSON.generate(id: "mem_1", content: "hello", createdAt: "2026-01-01T00:00:00Z")]
      when "/v1/search"
        [401, JSON.generate(message: "bad key")]
      else
        [404, "{}"]
      end
    end
    @server = MockServer.new(handler)
    @base_url = "http://127.0.0.1:#{@server.port}"
  end

  def teardown
    @server.stop
  end

  def test_memories_add_sends_headers_and_body
    client = Ledgermem::Client.new(api_key: "key", workspace_id: "ws", base_url: @base_url)
    mem = client.memories.add(content: "hello")

    assert_equal "mem_1", mem["id"]
    capture = @server.requests.first
    assert_equal "POST", capture[:method]
    assert_equal "/v1/memories", capture[:path]
    assert_equal "Bearer key", capture[:auth]
    assert_equal "ws", capture[:workspace]
    assert_equal "hello", capture[:body]["content"]
  end

  def test_search_raises_api_error
    client = Ledgermem::Client.new(api_key: "x", workspace_id: "ws", base_url: @base_url)
    err = assert_raises(Ledgermem::APIError) { client.search(query: "hi") }
    assert_equal 401, err.status
    assert_match(/bad key/, err.message)
  end
end
