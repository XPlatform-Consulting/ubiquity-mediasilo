module Ubiquity

  module MediaSilo

    class API

      class Response

        def self.from_http_response(http_response, options = { })
          _r = new(options)
          _r.from_http_response(http_response)
          _r
        end

        attr_accessor :raw, :raw_body, :body, :primary_key_name

        def initialize(args = { })
          @primary_key_name = args[:primary_key_name]

        end

        def result
          return false unless success?
          return body[primary_key_name] if primary_key_name and body.is_a?(Hash)
          self
        end
        alias :results :result

        def each(&block)
          value = result
          return value unless block_given?
          value.each &block
        end

        def each_with_index(&block)
          value = result
          return value unless block_given?
          value.each_with_index &block
        end

        def data
          @data ||= begin
            if body.is_a?(Hash)
              _data = primary_key_name ? body[primary_key_name] : body
            else
              _data = { }
            end
            _data
          end
        end

        def [](key)
          data[key]
        end

        # Sets the error class variable to a hash containing information pertaining to an error returned in a response to a request
        # @return [Hash]
        #   * :method [String] The API method being called when the error occurred
        #   * :code [Integer] The code returned in the response
        #   * :message [String] The message returned in the response
        #   * :request_attempt [Integer] The number of times the request was made
        def set_error
          _body = @body.is_a?(Hash) ? @body : { }
          @error = {
            :method => _body.fetch('METHOD', nil),
            :code => _body.fetch('CODE', nil),
            :message => _body.fetch('DESCRIPTION', nil),
            :detail => _body.fetch('DETAIL', nil),
            #:request_attempts => @request_attempt
          }
        end # set_error


        def from_http_response(http_response)
          @raw = http_response
          @raw_body = http_response.respond_to?(:body) ? http_response.body : nil

          return unless raw_body

          start_with = raw_body.strip[0]
          case start_with
            #when '{', '['
            #  @body = JSON.parse(raw_body) rescue { }
            when '<'
              title = raw_body[/<TITLE>(.*)<\/TITLE>/] ? $1 : ''
              body = raw_body[/<BODY.*>(.*)<\/BODY>/] ? $1 : raw_body

              @body = {
                'DESCRIPTION' => title,
                'DETAIL' => body,
                'STATUS' => 'error',
              }
            else
              @body = JSON.parse(raw_body) rescue { }
          end

          set_error if responded_with_error?
        end

        def success?
          body.respond_to?(:fetch) && (body.fetch('STATUS', false) == 'success')
        end

        def error?(params = {})
          !success?
        end # error?

        def error
          @error
        end

        def error_message
          error[:message]
        end # error_message

        def responded_with_error?
          body.respond_to?(:fetch) && (body.fetch('STATUS', false) == 'error')
        end # responded_with_error

        def next_page?
          success? and body.fetch['TOTAL', 0] > 0
        end

      end

    end

  end

end