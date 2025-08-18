# frozen_string_literal: true

require "test_helper"

module MCP
  class ContextDependentSchemaTest < ActiveSupport::TestCase
    # Static tool for comparison
    class StaticTool < Tool
      tool_name "static_tool"
      description "A tool with static schema"
      input_schema(properties: { name: { type: "string" } }, required: ["name"])

      class << self
        def call(name:, server_context: nil)
          Tool::Response.new([{ type: "text", text: "Static: #{name}" }])
        end
      end
    end

    # Context-dependent tool
    class DynamicTool < Tool
      tool_name "dynamic_tool"
      description "A tool with context-dependent schema"

      input_schema do |server_context|
        if server_context&.dig(:user, :role) == "admin"
          {
            properties: {
              secret_action: { type: "string" },
              target: { type: "string" }
            },
            required: ["secret_action", "target"]
          }
        else
          {
            properties: { action: { type: "string" } },
            required: ["action"]
          }
        end
      end

      class << self
        def call(secret_action: nil, target: nil, action: nil, server_context: nil)
          role = server_context&.dig(:user, :role) || "user"
          args = { secret_action: secret_action, target: target, action: action }.compact
          Tool::Response.new([{ type: "text", text: "Dynamic (#{role}): #{args}" }])
        end
      end
    end

    # Tool that returns InputSchema object
    class InputSchemaReturnTool < Tool
      tool_name "input_schema_return_tool"
      description "A tool that returns InputSchema object"

      input_schema do |server_context|
        if server_context&.dig(:user, :premium)
          Tool::InputSchema.new(
            properties: { premium_feature: { type: "string" } },
            required: ["premium_feature"]
          )
        else
          Tool::InputSchema.new(
            properties: { basic_feature: { type: "string" } },
            required: ["basic_feature"]
          )
        end
      end

      class << self
        def call(server_context: nil, **args)
          Tool::Response.new([{ type: "text", text: "Premium check: #{args}" }])
        end
      end
    end

    test "static tool behavior remains unchanged" do
      assert_equal "static_tool", StaticTool.name_value
      assert_equal "A tool with static schema", StaticTool.description_value

      # Schema should be the same regardless of context
      schema_no_context = StaticTool.input_schema_value
      schema_with_context = StaticTool.input_schema_value(server_context: { user: { role: "admin" } })

      assert_equal schema_no_context.to_h, schema_with_context.to_h
      assert_equal({ type: "object", properties: { name: { type: "string" } }, required: [:name] }, schema_no_context.to_h)
    end

    test "dynamic tool generates different schemas based on context" do
      # User schema
      user_schema = DynamicTool.input_schema_value(server_context: { user: { role: "user" } })
      expected_user_schema = {
        type: "object",
        properties: { action: { type: "string" } },
        required: [:action]
      }
      assert_equal expected_user_schema, user_schema.to_h

      # Admin schema
      admin_schema = DynamicTool.input_schema_value(server_context: { user: { role: "admin" } })
      expected_admin_schema = {
        type: "object",
        properties: {
          secret_action: { type: "string" },
          target: { type: "string" }
        },
        required: [:secret_action, :target]
      }
      assert_equal expected_admin_schema, admin_schema.to_h

      # No context (defaults to user)
      no_context_schema = DynamicTool.input_schema_value
      assert_equal expected_user_schema, no_context_schema.to_h
    end

    test "tool to_h includes context-resolved schema" do
      # User context
      user_tool_h = DynamicTool.to_h(server_context: { user: { role: "user" } })
      assert_equal "action", user_tool_h[:inputSchema][:properties].keys.first.to_s
      assert_equal [:action], user_tool_h[:inputSchema][:required]

      # Admin context
      admin_tool_h = DynamicTool.to_h(server_context: { user: { role: "admin" } })
      assert_equal ["secret_action", "target"], admin_tool_h[:inputSchema][:properties].keys.map(&:to_s).sort
      assert_equal [:secret_action, :target], admin_tool_h[:inputSchema][:required].sort
    end

    test "input schema generator can return InputSchema objects" do
      premium_schema = InputSchemaReturnTool.input_schema_value(server_context: { user: { premium: true } })
      basic_schema = InputSchemaReturnTool.input_schema_value(server_context: { user: { premium: false } })

      assert_equal [:premium_feature], premium_schema.required
      assert_equal [:basic_feature], basic_schema.required
    end

    test "invalid return type from generator raises error" do
      invalid_tool = Class.new(Tool) do
        input_schema { |_| "invalid" }
      end

      error = assert_raises(ArgumentError) do
        invalid_tool.input_schema_value(server_context: {})
      end

      assert_match(/Schema generator must return Hash or InputSchema, got String/, error.message)
    end

    test "server integration with context-dependent tools" do
      server = Server.new(
        name: "test_server",
        tools: [StaticTool, DynamicTool],
        server_context: { user: { role: "admin" } }
      )

      # Test tools list includes context-resolved schemas
      tools_list = server.send(:list_tools, {})

      static_tool_def = tools_list.find { |t| t[:name] == "static_tool" }
      dynamic_tool_def = tools_list.find { |t| t[:name] == "dynamic_tool" }

      # Static tool unchanged
      assert_equal [:name], static_tool_def[:inputSchema][:required]

      # Dynamic tool should show admin schema
      assert_equal [:secret_action, :target], dynamic_tool_def[:inputSchema][:required].sort
    end

    test "manual schema validation works correctly" do
      user_context = { user: { role: "user" } }
      admin_context = { user: { role: "admin" } }

      # Test user schema validation
      user_schema = DynamicTool.input_schema_value(server_context: user_context)
      user_args = { action: "list" }
      admin_args = { secret_action: "deploy", target: "production" }

      # User schema should accept user args
      refute user_schema.missing_required_arguments?(user_args)

      # User schema should reject admin args (missing "action")
      assert user_schema.missing_required_arguments?(admin_args)
      assert_equal [:action], user_schema.missing_required_arguments(admin_args)

      # Admin schema validation
      admin_schema = DynamicTool.input_schema_value(server_context: admin_context)

      # Admin schema should accept admin args
      refute admin_schema.missing_required_arguments?(admin_args)

      # Admin schema should reject user args (missing secret_action, target)
      assert admin_schema.missing_required_arguments?(user_args)
      assert_equal [:secret_action, :target], admin_schema.missing_required_arguments(user_args).sort
    end

    test "server tool call validation uses context-resolved schema" do
      # Admin server
      admin_server = Server.new(
        name: "admin_server",
        tools: [DynamicTool],
        server_context: { user: { role: "admin" } }
      )

      # User server
      user_server = Server.new(
        name: "user_server", 
        tools: [DynamicTool],
        server_context: { user: { role: "user" } }
      )

      # Admin call with admin arguments should work
      admin_request = {
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "dynamic_tool",
          arguments: { secret_action: "deploy", target: "production" }
        }
      }

      admin_response = admin_server.handle(admin_request)
      assert admin_response[:result]
      assert_match(/Dynamic \(admin\)/, admin_response[:result][:content][0][:text])

      # User call with user arguments should work
      user_request = {
        jsonrpc: "2.0", 
        id: 1,
        method: "tools/call",
        params: {
          name: "dynamic_tool",
          arguments: { action: "list" }
        }
      }

      user_response = user_server.handle(user_request)
      assert user_response[:result]
      assert_match(/Dynamic \(user\)/, user_response[:result][:content][0][:text])
    end

    test "backward compatibility with existing static schema declarations" do
      # Hash declaration
      hash_tool = Tool.define(
        name: "hash_tool",
        input_schema: { properties: { msg: { type: "string" } }, required: ["msg"] }
      ) { |msg:| Tool::Response.new([{ type: "text", text: msg }]) }

      schema = hash_tool.input_schema_value
      assert_equal [:msg], schema.required

      # InputSchema object declaration
      schema_obj = Tool::InputSchema.new(properties: { data: { type: "string" } }, required: ["data"])
      obj_tool = Tool.define(
        name: "obj_tool",
        input_schema: schema_obj
      ) { |data:| Tool::Response.new([{ type: "text", text: data }]) }

      schema = obj_tool.input_schema_value
      assert_equal [:data], schema.required
    end

    test "tool inheritance properly initializes schema generator" do
      parent_tool = Class.new(Tool) do
        input_schema { |_| { properties: { parent: { type: "string" } }, required: ["parent"] } }
      end

      child_tool = Class.new(parent_tool) do
        input_schema { |_| { properties: { child: { type: "string" } }, required: ["child"] } }
      end

      parent_schema = parent_tool.input_schema_value(server_context: {})
      child_schema = child_tool.input_schema_value(server_context: {})

      assert_equal [:parent], parent_schema.required
      assert_equal [:child], child_schema.required
    end
  end
end