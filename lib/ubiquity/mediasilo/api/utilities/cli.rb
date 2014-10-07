require 'json'

require 'ubiquity/mediasilo/cli'
require 'ubiquity/mediasilo/api/utilities'
module Ubiquity

  module MediaSilo

    class API

      class Utilities

        class CLI < MediaSilo::CLI

          attr_accessor :logger, :api, :initial_args

          LOGGING_LEVELS = {
              :debug => Logger::DEBUG,
              :info => Logger::INFO,
              :warn => Logger::WARN,
              :error => Logger::ERROR,
              :fatal => Logger::FATAL
          }

          def self.parse_arguments(arguments = ARGV)
            options = {
              :options_file_path => "~/.options/#{File.basename($0, '.*')}"
            }
            op = OptionParser.new
            op.on('--mediasilo-hostname HOSTNAME', 'The hostname to use when authenticating with the MediaSilo API.') { |v| options[:hostname] = v }
            op.on('--mediasilo-username USERNAME', 'The username to use when authenticating with the MediaSilo API.') { |v| options[:username] = v }
            op.on('--mediasilo-password PASSWORD', 'The password to use when authenticating with the MediaSilo API.') { |v| options[:password] = v }
            op.on('--method-name METHODNAME', 'The name of the method to invoke.') { |v| options[:method_name] = v }
            op.on('--method-arguments JSON', 'The arguments to pass to the method') { |v| options[:method_arguments] = v }
            op.on('--log-to FILENAME', 'Log file location.', "\tdefault: STDERR") { |v| options[:log_to] = v }
            op.on('--log-level LEVEL', LOGGING_LEVELS.keys, "Logging level. Available Options: #{LOGGING_LEVELS.keys.join(', ')}",
                  "\tdefault: #{LOGGING_LEVELS.invert[options[:log_level]]}") { |v| options[:log_level] = LOGGING_LEVELS[v] }
            op.on('--[no-]options-file [FILENAME]', 'Path to a file which contains default command line arguments.', "\tdefault: #{options[:options_file_path]}" ) { |v| options[:options_file_path] = v}
            op.on('--[no-]pretty-print', 'Determines if the output will be formatted for easier human readability.') { |v| options[:pretty_print] = v }
            op.on_tail('-h', '--help', 'Show this message.') { puts op; exit }
            op.parse!(arguments.dup)

            options_file_path = options[:options_file_path]
            # Make sure that options from the command line override those from the options file
            op.parse!(arguments.dup) if op.load(options_file_path)
            options
          end

          def self.run(args_array = ARGV)
            args = parse_arguments(args_array)
            new(args).run
          end

          def initialize(args = { })
            args = @initial_args = args.dup
            initialize_logger(args)
          end

          def initialize_logger(args = { })
            @logger = args[:logger] ||= Logger.new(args[:log_to] || STDERR)
            logger.level = args[:log_level] if args[:log_level]
            logger
          end

          def run(args = initial_args)
            method_name = args[:method_name]
            raise ArgumentError, ':method_name is a required argument.' unless method_name

            method_arguments = args[:method_arguments]
            if method_arguments
              method_arguments = JSON.parse(method_arguments) if method_arguments.is_a?(String) and method_arguments.start_with?('{', '[')
              method_arguments = Hash[method_arguments.map { |k,v| k = k.to_sym if k.respond_to?(:to_sym); [ k, v ] }] if method_arguments.is_a?(Hash)
            end

            initialize_api(args)

            response = case method_name.to_sym
              when :asset_create; asset_create(method_arguments)
              when :asset_edit; asset_edit(method_arguments)
              when :asset_create_using_path; asset_create_using_path(method_arguments)
            end
            abort("Error: #{response.error_message}") if response.respond_to?(:success?) and !response.success?
            abort("Error: #{api.error_message}") unless api.success?

            if args[:pretty_print]
              if response.is_a?(String) and response.lstrip.start_with?('{', '[')
                puts JSON.pretty_generate(JSON.parse(response))
              else
                pp response
              end
            else
              response = JSON.generate(response) if response.is_a?(Hash) or response.is_a?(Array)
              puts response
            end
          end

          def initialize_api(args = { })
            @api = MediaSilo::API::Utilities.new(args)
            api.initialize_session(args)
            abort(api.error_message) unless api.success?
            api
          end

          def asset_copy(args = { })
            response = api.asset_copy_extended(args)
            response
          end

          def asset_create(args = { })
            case args
            when Hash
              url = args.delete('url')
              options = args.delete('options') { { } }
            when Array
              url, args, options = *args
              options ||= { }
            end

            args[:return_extended_response] = true
            response = api.asset_create(url, args, options)
            response
          end

          def asset_create_using_path(args = { })
            response = api.asset_create_using_path(args)
            response
          end

          def asset_edit(args = { })
            response = api.asset_edit_extended(args)
            response
          end

          # CLI
        end

        # Utilities
      end

      # API
    end

    # MediaSilo
  end

  # Ubiquity
end