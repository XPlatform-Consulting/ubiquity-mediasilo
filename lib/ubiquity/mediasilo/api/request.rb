module Ubiquity

  module MediaSilo

    class API

      class Request

        attr_reader :api_method_name, :initial_api_arguments, :initial_options
        attr_accessor :api_method_arguments, :options
        alias :method_name :api_method_name
        alias :method_arguments :api_method_arguments

        attr_accessor :connection
        attr_reader :http_responses, :http_response

        attr_reader :responses, :response

        def initialize(api_method_name, api_method_arguments = { }, options = { })
          @initial_api_arguments = api_method_arguments.dup.freeze
          @initial_options = options.dup.freeze

          @api_method_name = api_method_name
          @api_method_arguments = api_method_arguments
          convert_page_number
          @options = options

          @connection = options[:connection]
        end

        def to_xml(args = api_method_arguments)
          xml = "<?xml version='1.0' encoding='UTF-8'?><request>"
          args.each { |key, value|
            #[*value].each { |v| xml << "<#{key}><![CDATA[#{v}]]></#{key}>" }
            _value = case value
                       when Array; value.join(',')
                       when TrueClass; 1
                       when FalseClass; 0
                       else value
                     end
            xml << "<#{key}><![CDATA[#{_value}]]></#{key}>"
          }
          xml << '</request>'
          xml
        end

        def to_hash
          { :api_method => api_method_name, :api_method_arguments => api_method_arguments, :options => options }
        end

        def inspect
          to_hash.inspect
        end

        def http_responses
          @http_responses ||= [ ]
        end

        def last_http_response
          http_responses.last
        end
        #alias :http_response :last_http_response

        def responses
          @responses ||= [ ]
        end

        def last_response
          responses.last
        end
        #alias :response :last_response

        def next_page?
          response.next_page?
        end

        def next_page
          response.next_page
        end

        def convert_page_number
          page_number = api_method_arguments[:page] ||= api_method_arguments.delete('page') { }
          #first_page = _request.options[:first_page]
          if page_number.nil? or page_number == -1 or (page_number.respond_to?(:downcase) and [:all, 'all'].include? page_number.downcase)

            # asset.search and asset.advancedsearch results come from Amazon Cloud Search and use 0 instead of 1 as the first page number
            if %w(asset.cloudsearch asset.cloudadvancedsearch asset.search asset.advancedsearch).include? api_method_name.downcase
              page_number = 0
              #pageoffset = 1
            else
              page_number = 1
              #pageoffset = 0
            end
          end
          api_method_arguments[:page] = page_number if page_number
        end

        def get_next_page(_request = self)
          #puts "API METHOD ARGUMENTS: #{_request.api_method_arguments.inspect}"
          #page_number = _request.api_method_arguments[:page] ||= _request.api_method_arguments.delete('page') { }
          # #first_page = _request.options[:first_page]
          # if page_number.nil? or page_number == -1 or (page_number.respond_to?(:downcase) and [:all, 'all'].include? page_number.downcase)
          #
          #   # asset.search and asset.advancedsearch results come from Amazon Cloud Search and use 0 instead of 1 as the first page number
          #   if %w(asset.cloudsearch asset.cloudadvancedsearch asset.search asset.advancedsearch).include? api_method_name.downcase
          #     page_number = 0
          #     pageoffset = 1
          #   else
          #     page_number = 1
          #     pageoffset = 0
          #   end
          # else
          #   page_number += 1
          # end
          #_request.api_method_arguments[:page] = page_number

          page_number = _request.api_method_arguments[:page]
          page_number += 1
          get_page(page_number)
        end

        def get_page(page)
          request_for_page = Request.new(api_method_name, api_method_arguments.merge(:page => page), options)
          request_for_page.send
        end

        def get_all_pages
          # return get_pages(method, params) if params.has_key?('page') and ([-1, :all, 'all', nil].any? { |v| params['page'] == v } or params['page'].is_a? Array)

          pages = [ ]
          pages << get_next_page
          pages
        end


        def send
          @http_response = connection.send_api_request(self)
          http_responses << http_response

          @response = Response.from_http_response(http_response, options.merge(:request => self))
          responses << response

          response
        end

      end

      class Paginator

        attr_accessor :request, :first_page, :page

        def initialize(args = { })
          @initial_request = args[:request]
          @request = @initial_request.dup

          # asset.search and asset.advancedsearch results come from Amazon Cloud Search and use 0 instead of 1 as the first page number
          if %w(asset.cloudsearch asset.cloudadvancedsearch asset.search asset.advancedsearch).include? request.api_method_name.downcase
            @first_page = args[:first_page] || 0
            @page_offset = args[:page_offset] || 1
          else
            @first_page = args[:first_page] || 1
            @page_offset = args[:page_offset] || 0
          end

          @page = request.api_method_arguments('page', first_page)
          if page.nil? or (page.respond_to?(:downcase) and [:all, 'all'].include? page.downcase)
            @page = first_page
          end

        end


      end

    end

  end

end