# frozen_string_literal: true

# Example MCP server demonstrating context-dependent tool schemas
#
# To test different user roles:
# - Regular user: ruby examples/stdio_server.rb
# - Admin user: USER_ROLE=admin ruby examples/stdio_server.rb
#
# The AdminTool will show different input schemas and behavior based on the user role.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "mcp"
require "mcp/server/transports/stdio_transport"

# Create a simple tool
class ExampleTool < MCP::Tool
  description "A simple example tool that adds two numbers"
  input_schema(
    properties: {
      a: { type: "number" },
      b: { type: "number" },
    },
    required: ["a", "b"],
  )

  class << self
    def call(a:, b:)
      MCP::Tool::Response.new([{
        type: "text",
        text: "The sum of #{a} and #{b} is #{a + b}",
      }])
    end
  end
end

# Create a context-dependent tool that changes schema based on user permissions
class AdminTool < MCP::Tool
  description "A tool with context-dependent schema based on user role"
  
  input_schema do |server_context|
    user_role = server_context&.dig(:user, :role)
    
    if user_role == "admin"
      {
        properties: {
          action: { 
            type: "string", 
            enum: ["deploy", "restart", "configure", "monitor"]
          },
          target: { 
            type: "string",
            description: "Target environment (production, staging, etc.)"
          },
          force: { 
            type: "boolean", 
            description: "Force the action without confirmation"
          }
        },
        required: ["action", "target"]
      }
    else
      {
        properties: {
          action: { 
            type: "string", 
            enum: ["status", "logs", "metrics"]
          }
        },
        required: ["action"]
      }
    end
  end

  class << self
    def call(action:, target: nil, force: false, server_context: nil)
      user_role = server_context&.dig(:user, :role) || "user"
      
      case user_role
      when "admin"
        MCP::Tool::Response.new([{
          type: "text",
          text: "Admin action '#{action}' executed on '#{target}' (force: #{force})"
        }])
      else
        MCP::Tool::Response.new([{
          type: "text", 
          text: "User action '#{action}' executed (read-only access)"
        }])
      end
    end
  end
end

# Create a simple prompt
class ExamplePrompt < MCP::Prompt
  description "A simple example prompt that echoes back its arguments"
  arguments [
    MCP::Prompt::Argument.new(
      name: "message",
      description: "The message to echo back",
      required: true,
    ),
  ]

  class << self
    def template(args, server_context:)
      MCP::Prompt::Result.new(
        messages: [
          MCP::Prompt::Message.new(
            role: "user",
            content: MCP::Content::Text.new(args[:message]),
          ),
        ],
      )
    end
  end
end

# Set up the server with context
# In a real application, you would determine the user context from authentication
user_context = {
  user: {
    id: "user123",
    role: ENV["USER_ROLE"] || "user" # Try: USER_ROLE=admin ruby examples/stdio_server.rb
  }
}

server = MCP::Server.new(
  name: "example_server",
  version: "1.0.0",
  tools: [ExampleTool, AdminTool],
  prompts: [ExamplePrompt],
  server_context: user_context,
  resources: [
    MCP::Resource.new(
      uri: "https://test_resource.invalid",
      name: "test-resource",
      title: "Test Resource",
      description: "Test resource that echoes back the uri as its content",
      mime_type: "text/plain",
    ),
  ],
)

server.define_tool(
  name: "echo",
  description: "A simple example tool that echoes back its arguments",
  input_schema: { properties: { message: { type: "string" } }, required: ["message"] },
) do |message:|
  MCP::Tool::Response.new(
    [
      {
        type: "text",
        text: "Hello from echo tool! Message: #{message}",
      },
    ],
  )
end

server.resources_read_handler do |params|
  [{
    uri: params[:uri],
    mimeType: "text/plain",
    text: "Hello, world! URI: #{params[:uri]}",
  }]
end

# Create and start the transport
transport = MCP::Server::Transports::StdioTransport.new(server)
transport.open
