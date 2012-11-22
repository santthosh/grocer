require 'grocer'
require 'grocer/no_gateway_error'
require 'grocer/no_port_error'
require 'grocer/certificate_expired_error'
require 'grocer/ssl_connection'

module Grocer
  class Connection
    attr_reader :certificate, :passphrase, :gateway, :port, :retries
    
    DEFAULT_SELECT_WAIT = 0.5

    def initialize(options = {})
      @certificate = options.fetch(:certificate) { nil }
      @passphrase = options.fetch(:passphrase) { nil }
      @gateway = options.fetch(:gateway) { fail NoGatewayError }
      @port = options.fetch(:port) { fail NoPortError }
      @retries = options.fetch(:retries) { 3 }
    end

    def read(size = nil, buf = nil)
      with_connection do
        ssl.read(size, buf)
      end
    end

    def write(content)
      with_connection do
        ssl.write(content)
        
        read, write, error = IO.select [ssl], [], [ssl], DEFAULT_SELECT_WAIT)
        
        # If there is an error disconnect and raise an exception
        if !error.nil? && !error.first.nil?
          destroy_connection
          raise RuntimeError "IO.select has reported an unexpected error. Please disconnect and retry"
        end
        
        # If there is an error disconnect and raise an exception
        if !read.nil? && !read.first.nil?
          error_response = ssl.read_nonblock 6
          error = ErrorResponse.new error_response, content
          destroy_connection
          raise error
        end
        
      end
    end
    
    
    

    def connect
      ssl.connect unless ssl.connected?
    end

    private

    def ssl
      @ssl_connection ||= build_connection
    end

    def build_connection
      Grocer::SSLConnection.new(certificate: certificate,
                                passphrase: passphrase,
                                gateway: gateway,
                                port: port)
    end

    def destroy_connection
      return unless @ssl_connection

      @ssl_connection.disconnect rescue nil
      @ssl_connection = nil
    end

    def with_connection
      attempts = 1
      begin
        connect
        yield
      rescue => e
        if e.class == OpenSSL::SSL::SSLError && e.message =~ /certificate expired/i
          e.extend(CertificateExpiredError)
          raise
        end

        raise unless attempts < retries

        destroy_connection
        attempts += 1
        retry
      end
    end
  end
end
