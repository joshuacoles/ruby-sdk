# frozen_string_literal: true

require "test_helper"

module MCP
  class Server
    module Transports
      class InProcessTransportTest < Minitest::Test
        def setup
          @server = MCP::Server.new(name: "test_server")
          @client_transport = Minitest::Mock.new
          @transport = MCP::Server::Transports::InProcessTransport.new(@server, @client_transport)
        end

        def test_initialize
          assert_equal @server, @transport.instance_variable_get(:@server)
          refute @transport.instance_variable_get(:@open)
        end

        def test_open
          @transport.open
          assert @transport.instance_variable_get(:@open)
        end

        def test_close
          @transport.open
          @transport.close
          refute @transport.instance_variable_get(:@open)
        end

        def test_send_response
          message = { "jsonrpc" => "2.0", "id" => 1, "result" => {} }
          result = @transport.send_response(message)
          assert_equal message, result
        end

        def test_send_notification_when_open
          @transport.open
          method_name = "notifications/tools/list_changed"
          params = { "data" => "test" }

          @client_transport.expect(:receive_notification, nil, [method_name, params])

          result = @transport.send_notification(method_name, params)
          assert result

          @client_transport.verify
        end

        def test_send_notification_when_closed
          method_name = "notifications/tools/list_changed"
          params = { "data" => "test" }

          result = @transport.send_notification(method_name, params)
          refute result
        end

        def test_send_notification_without_client_transport
          transport = MCP::Server::Transports::InProcessTransport.new(@server, nil)
          transport.open

          result = transport.send_notification("test_method")
          refute result
        end

        def test_send_notification_handles_errors
          @transport.open
          method_name = "notifications/tools/list_changed"

          @client_transport.expect(:receive_notification, nil) do |method, params|
            raise StandardError, "Client transport error"
          end

          # Mock the exception reporter
          exception_reporter = Minitest::Mock.new
          exception_reporter.expect(:call, nil) do |exception, context|
            assert_instance_of StandardError, exception
            assert_equal "Client transport error", exception.message
            assert_equal "Failed to send notification in in-process transport", context[:error]
            assert_equal method_name, context[:method]
          end

          MCP.configuration.exception_reporter = exception_reporter

          result = @transport.send_notification(method_name)
          refute result

          @client_transport.verify
          exception_reporter.verify
        ensure
          # Reset exception reporter
          MCP.configuration.exception_reporter = MCP::Configuration.new.exception_reporter
        end

        def test_handle_json_request
          request = '{"jsonrpc":"2.0","id":1,"method":"ping"}'
          expected_response = '{"jsonrpc":"2.0","id":1,"result":{}}'

          @server.stub(:handle_json, expected_response) do
            result = @transport.handle_json_request(request)
            assert_equal expected_response, result
          end
        end

        def test_handle_request
          request = { "jsonrpc" => "2.0", "id" => 1, "method" => "ping" }
          expected_response = { "jsonrpc" => "2.0", "id" => 1, "result" => {} }

          @server.stub(:handle, expected_response) do
            result = @transport.handle_request(request)
            assert_equal expected_response, result
          end
        end
      end
    end
  end
end