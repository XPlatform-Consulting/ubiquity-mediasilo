require 'net/http'
require 'net/https' unless RUBY_VERSION >= '1.9'
require 'uri'

module Ubiquity

  module MediaSilo

    class API

      class Connection

        attr_reader :host_address, :base_uri, :parsed_base_uri
        attr_reader :http, :read_timeout, :use_ssl, :verify_ssl

        attr_accessor :session_key

        def default_host_address
          @default_host_address ||= DEFAULT_HOST_ADDRESS
        end

        def default_timeout
          @default_timeout ||= DEFAULT_TIMEOUT
        end

        def initialize(args = { })
          @host_address = args[:host_address] || default_host_address

          parsed_host_address = URI.parse(host_address)

          @use_ssl = args.fetch(:use_ssl, parsed_host_address.scheme == 'https')
          @verify_ssl = args.fetch(:verify_ssl, true)

          @read_timeout = args.fetch(:read_timeout, args.fetch(:timeout, default_timeout))
          #@ssl_timeout = args.fetch(:ssl_timeout, args.fetch(:timeout, DEFAULT_TIMEOUT))

          @base_uri = parsed_host_address.scheme ? host_address : "http#{use_ssl ? 's' : ''}://#{host_address}"
          @base_uri = base_uri[0..-2] while base_uri.end_with?('/')

          @parsed_base_uri = URI.parse(base_uri)
          initialize_http
        end

        def initialize_http
          @http = Net::HTTP.new(parsed_base_uri.host, parsed_base_uri.port)
          configure_http_ssl if use_ssl
          http.read_timeout if read_timeout
        end

        def configure_http_ssl
          http.use_ssl = use_ssl ? true : false
          return unless use_ssl
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE unless verify_ssl
        end

        def http_request_as_hash
          @http_request_as_hash ||= begin
            request_hash = {
              :method => @http_request.method,
              :path => @http_request.path
            }
            request_hash[:body] = @http_request.body if @http_request.request_body_permitted?
            request_hash
          end
        end # http_request_as_hash

        def http_response_as_hash
          @http_response_as_hash ||= begin
            response_hash = {
              :code => @http_response.code,
              :message => @http_response.message,
            }
            response_hash[:body] = @http_response.body if @http_request.response_body_permitted?
            response_hash
          end
        end # response_as_hash

        def send_request(http_request)
          @http_request_as_hash = nil
          @http_response_as_hash = nil

          @http_request = http_request

          @request_time_start = Time.now

          @http_response = http.request(@http_request)

          @request_time_end = Time.now
          @request_time_elapsed = @request_time_end - @request_time_start

          @http_response
        end

        # Takes an API::Request and returns a HTTP::Request
        # @param [MediaSilo::API::Request]
        # @return [Net::HTTP::Post]
        def api_request_to_http_request(api_request)
          query = "/?method=#{api_request.api_method_name}&returnformat=json"
          http_request = Net::HTTP::Post.new(query)
          http_request.content_type = 'text/xml'
          http_request.body = api_request.to_xml
          http_request
        end

        def send_api_request(api_request)
          api_request.api_method_arguments[:session] ||= session_key if api_request.api_method_arguments.has_key?(:session)
          http_request = api_request_to_http_request(api_request)
          send_request(http_request)
        end


      end

    end

  end

end