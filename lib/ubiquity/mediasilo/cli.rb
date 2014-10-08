#require 'ubiquity/cli'
require 'logger'
require 'optparse'

module Ubiquity

  module MediaSilo

    class CLI

      attr_accessor :logger

      LOGGING_LEVELS = {
          :debug => Logger::DEBUG,
          :info => Logger::INFO,
          :warn => Logger::WARN,
          :error => Logger::ERROR,
          :fatal => Logger::FATAL
      }

      def self.run
        new.run
      end

      def run

      end

      def parse_arguments

      end

    end

  end

end