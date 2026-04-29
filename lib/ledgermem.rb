# frozen_string_literal: true

require "json"
require "net/http"
require "socket"
require "time"
require "uri"

require_relative "getmnemo/version"

module Ledgermem
  DEFAULT_BASE_URL = "https://api.getmnemo.xyz"
  USER_AGENT = "getmnemo-ruby/#{VERSION}"
  DEFAULT_TIMEOUT = 30
  DEFAULT_MAX_RETRIES = 3
  RETRY_BASE_DELAY = 0.2
  RETRY_MAX_DELAY = 5.0

  RETRYABLE_TRANSPORT_ERRORS = [
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    Errno::EHOSTUNREACH,
    Errno::ENETUNREACH,
    Errno::ETIMEDOUT,
    Net::OpenTimeout,
    Net::ReadTimeout,
    EOFError,
    SocketError,
    IOError,
  ].freeze

  class Error < StandardError; end

  class APIError < Error
    attr_reader :status, :body

    def initialize(status:, message:, body:)
      super("getmnemo: #{status} #{message}")
      @status = status
      @body = body
    end
  end

  class Client
    attr_reader :base_url

    def initialize(api_key: nil, workspace_id: nil, base_url: nil, timeout: DEFAULT_TIMEOUT, max_retries: DEFAULT_MAX_RETRIES)
      @api_key      = api_key      || ENV["GETMNEMO_API_KEY"]
      @workspace_id = workspace_id || ENV["GETMNEMO_WORKSPACE_ID"]
      @base_url     = (base_url    || ENV["GETMNEMO_API_URL"] || DEFAULT_BASE_URL).chomp("/")
      @timeout      = timeout
      @max_retries  = [max_retries.to_i, 0].max
    end

    def search(query:, limit: nil, actor_id: nil)
      body = { query: query }
      body[:limit] = limit if limit
      body[:actorId] = actor_id if actor_id
      request(:post, "/v1/search", body: body)
    end

    def memories
      @memories ||= Memories.new(self)
    end

    def request(method, path, body: nil, query: nil)
      uri = URI.join("#{@base_url}/", path.sub(%r{\A/}, ""))
      uri.query = URI.encode_www_form(query) if query && !query.empty?

      attempt = 0
      loop do
        begin
          req = build_request(method, uri, body)
          res = Net::HTTP.start(uri.hostname, uri.port,
                                use_ssl: uri.scheme == "https",
                                open_timeout: @timeout,
                                read_timeout: @timeout) do |http|
            http.request(req)
          end
        rescue *RETRYABLE_TRANSPORT_ERRORS => e
          if attempt < @max_retries
            sleep(retry_delay(attempt, nil))
            attempt += 1
            next
          end
          raise APIError.new(status: 0, message: e.message, body: "")
        end

        status = res.code.to_i
        if retryable?(status) && attempt < @max_retries
          sleep(retry_delay(attempt, res["retry-after"]))
          attempt += 1
          next
        end
        return handle_response(res)
      end
    end

    private

    def build_request(method, uri, body)
      klass = {
        get:    Net::HTTP::Get,
        post:   Net::HTTP::Post,
        patch:  Net::HTTP::Patch,
        delete: Net::HTTP::Delete
      }.fetch(method)

      req = klass.new(uri.request_uri)
      req["Authorization"]  = "Bearer #{@api_key}" if @api_key
      req["x-workspace-id"] = @workspace_id if @workspace_id
      req["Accept"]         = "application/json"
      req["User-Agent"]     = USER_AGENT
      if body
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      end
      req
    end

    def handle_response(res)
      status = res.code.to_i
      raw = res.body.to_s

      if status >= 400
        message = parse_message(raw)
        raise APIError.new(status: status, message: message, body: raw)
      end

      return nil if status == 204 || raw.empty?

      JSON.parse(raw)
    end

    def retryable?(status)
      # 501 Not Implemented is permanent — retrying wastes round-trips.
      return false if status == 501
      status == 429 || (status >= 500 && status < 600)
    end

    def retry_delay(attempt, retry_after)
      hint = parse_retry_after(retry_after)
      return [hint, RETRY_MAX_DELAY].min if hint

      base = RETRY_BASE_DELAY * (2**attempt)
      capped = [base, RETRY_MAX_DELAY].min
      # Full jitter.
      rand * capped
    end

    def parse_retry_after(value)
      return nil if value.nil? || value.to_s.strip.empty?
      raw = value.to_s.strip
      secs = Float(raw) rescue nil
      return [secs, 0].max if secs
      # HTTP-date form.
      begin
        when_at = Time.httpdate(raw)
        delta = when_at - Time.now
        delta.positive? ? delta : 0
      rescue ArgumentError
        nil
      end
    end

    def parse_message(raw)
      data = JSON.parse(raw)
      data["message"] || data["error"] || ""
    rescue JSON::ParserError
      ""
    end
  end

  class Memories
    def initialize(client)
      @client = client
    end

    def add(content:, metadata: nil, actor_id: nil)
      body = { content: content }
      body[:metadata] = metadata if metadata
      body[:actorId] = actor_id if actor_id
      @client.request(:post, "/v1/memories", body: body)
    end

    def update(id, content: nil, metadata: nil)
      body = {}
      body[:content] = content unless content.nil?
      body[:metadata] = metadata unless metadata.nil?
      @client.request(:patch, "/v1/memories/#{escape(id)}", body: body)
    end

    def delete(id)
      @client.request(:delete, "/v1/memories/#{escape(id)}")
    end

    def list(limit: nil, cursor: nil, actor_id: nil)
      query = {}
      query[:limit] = limit if limit
      query[:cursor] = cursor if cursor
      query[:actorId] = actor_id if actor_id
      @client.request(:get, "/v1/memories", query: query)
    end

    private

    # URI.encode_www_form_component is form-encoding, which turns space
    # into "+". That is wrong for path segments (RFC 3986 expects "%20")
    # and would route an id like "foo bar" to "foo+bar" on the server.
    def escape(id)
      str = id.to_s
      out = +""
      str.each_byte do |b|
        if (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) ||
           [0x2D, 0x2E, 0x5F, 0x7E].include?(b) # - . _ ~
          out << b.chr
        else
          out << format("%%%02X", b)
        end
      end
      out
    end
  end
end
