# frozen_string_literal: true

require_relative "../../transport"
require "json"

module MCP
  class Server
    module Transports
      class InProcessTransport < Transport
        attr_reader :client_transport

        def initialize(server, client_transport)
          super(server)
          @client_transport = client_transport
          @open = false
        end

        def open
          @open = true
          # In-process transport doesn't need a persistent connection loop
          # as requests are handled synchronously
        end

        def close
          @open = false
        end

        def send_response(message)
          # In-process transport doesn't need to send responses explicitly
          # as they are returned directly from handle_json_request
          return message
        end

        def send_notification(method, params = nil)
          return false unless @open && @client_transport

          begin
            @client_transport.receive_notification(method, params)
            true
          rescue => e
            MCP.configuration.exception_reporter.call(e, { 
              error: "Failed to send notification in in-process transport",
              method: method,
              params: params
            })
            false
          end
        end

        # Override the base class method to handle requests synchronously
        def handle_json_request(request)
          response = @server.handle_json(request)
          response
        end

        def handle_request(request)
          response = @server.handle(request)
          response
        end
      end
    end
  end
end