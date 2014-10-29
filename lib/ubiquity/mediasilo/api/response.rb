module Ubiquity

  module MediaSilo

    class API

      class Response

        def self.from_http_response(http_response, options = { })
          _r = new(options)
          _r.from_http_response(http_response)
          _r
        end

        def self.parse_response_body(response_body)
          return { } unless response_body
          start_with = response_body.strip[0]
          case start_with
            #when '{', '['
            #  @body = JSON.parse(raw_body) rescue { }
            when '<'
              title = response_body[/<TITLE>(.*)<\/TITLE>/] ? $1 : ''
              body = response_body[/<BODY.*>(.*)<\/BODY>/] ? $1 : response_body

              {
                'DESCRIPTION' => title,
                'DETAIL' => body,
                'STATUS' => 'error',
              }
            else
              JSON.parse(response_body) rescue { }
          end
        end

        attr_accessor :raw, :primary_key_name, :request

        def initialize(args = { })
          @primary_key_name = args[:primary_key_name]
          @request = args[:request]
        end

        # @return [Hash]
        def parse_body(_body = body)
          self.class.parse_response_body(_body)
        end

        # @return [Hash]
        def body_parsed
          @body_parsed ||= parse_body
        end
        alias :parsed :body_parsed

        # @return [Boolean, Hash, Response]
        def result
          return false unless success?
          return body_parsed[primary_key_name] if primary_key_name
          self
        end
        alias :results :result

        def each(&block)
          return data unless block_given?
          data.each &block
        end

        def each_with_index(&block)
          return data unless block_given?
          data.each_with_index &block
        end

        def data
          @data ||= (primary_key_name ? body_parsed[primary_key_name] : body_parsed)
        end

        def [](key)
          data[key]
        end

        # Creates a hash containing information pertaining to an error returned in a response to a request
        # @return [Hash]
        #   * :method [String] The API method being called when the error occurred
        #   * :code [Integer] The code returned in the response
        #   * :message [String] The message returned in the response
        #   * :request_attempt [Integer] The number of times the request was made
        def parse_error
          _body = body_parsed
          {
            :method => _body['METHOD'],
            :code => _body['CODE'],
            :message => _body['DESCRIPTION'],
            :detail => _body['DETAIL'],
            #:request_attempts => @request_attempt
          }
        end # set_error

        def from_http_response(http_response)
          @raw = http_response
        end

        def raw_body?
          raw.respond_to?(:body)
        end
        alias :body? :raw_body?

        def raw_body
          raw_body? ? raw.body : nil
        end
        alias :body :raw_body

        # @return [Boolean]
        def success?
          (body_parsed.fetch('STATUS', false) == 'success')
        end

        # @return [Boolean]
        def error?
          !success?
        end # error?

        # @return [False, Hash]
        def error
          @error ||= parse_error
        end

        def error_message
          error[:message]
        end # error_message

        def responded_with_error?
          (body_parsed.fetch('STATUS', false) == 'error')
        end # responded_with_error

        def next_page?
          success? and body_parsed.fetch('TOTAL', 0) > 0
        end

      end

    end

  end

end