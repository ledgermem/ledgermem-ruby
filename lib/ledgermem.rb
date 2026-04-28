# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

require_relative "ledgermem/version"

module Ledgermem
  DEFAULT_BASE_URL = "https://api.proofly.dev"
  USER_AGENT = "ledgermem-ruby/#{VERSION}"
  DEFAULT_TIMEOUT = 30
  DEFAULT_MAX_RETRIES = 3
  RETRY_BASE_DELAY = 0.2
  RETRY_MAX_DELAY = 5.0

  class Error < StandardError; end

  class APIError < Error
    attr_reader :status, :body

    def initialize(status:, message:, body:)
      super("ledgermem: #{status} #{message}")
      @status = status
      @body = body
    end
  end

  class Client
    attr_reader :base_url

    def initialize(api_key: nil, workspace_id: nil, base_url: nil, timeout: DEFAULT_TIMEOUT, max_retries: DEFAULT_MAX_RETRIES)
      @api_key      = api_key      || ENV["LEDGERMEM_API_KEY"]
      @workspace_id = workspace_id || ENV["LEDGERMEM_WORKSPACE_ID"]
      @base_url     = (base_url    || ENV["LEDGERMEM_API_URL"] || DEFAULT_BASE_URL).chomp("/")
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
        req = build_request(method, uri, body)
        res = Net::HTTP.start(uri.hostname, uri.port,
                              use_ssl: uri.scheme == "https",
                              open_timeout: @timeout,
                              read_timeout: @timeout) do |http|
          http.request(req)
        end

        status = res.code.to_i
        if retryable?(status) && attempt < @max_retries
          sleep(retry_delay(attempt))
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
      status == 429 || (status >= 500 && status < 600)
    end

    def retry_delay(attempt)
      base = RETRY_BASE_DELAY * (2**attempt)
      capped = [base, RETRY_MAX_DELAY].min
      # Full jitter.
      rand * capped
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

    def escape(id)
      URI.encode_www_form_component(id.to_s)
    end
  end
end
