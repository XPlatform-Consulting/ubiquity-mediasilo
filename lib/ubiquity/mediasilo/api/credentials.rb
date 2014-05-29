module Ubiquity

  module MediaSilo

    class API

      # A class to redact the password if inspect or to_s is called on it
      class Credentials

        def initialize(args = { })
          @hostname = args[:hostname]
          @username = args[:username]
          @password = args[:password]
          @redact_password = args.fetch(:redact_password, true)
        end

        def redact_password?
          @redact_password ? true : false
        end

        def username
          @username
        end

        def password
          @password
        end

        def hostname
          @hostname
        end

        def inspect
          @as_string ||= %({ :hostname => #{hostname},  :username => #{username}, :password => #{@redact_password ? '**REDACTED***' : password} })
        end
        alias :to_s :inspect

        def to_hash
          @as_hash ||= { :hostname => hostname, :username => username, :password => password }
        end

        def [](key)
          to_hash[key]
        end

      end

    end

  end

end
