# frozen_string_literal: true

require "test_helper"

module MCP
  class ContextDependentDescriptionTest < ActiveSupport::TestCase
    # Static tool for comparison
    class StaticTool < Tool
      tool_name "static_tool"
      description "A tool with static description"
      input_schema(properties: { name: { type: "string" } }, required: ["name"])

      class << self
        def call(name:, server_context: nil)
          Tool::Response.new([{ type: "text", text: "Static: #{name}" }])
        end
      end
    end

    # Context-dependent tool description
    class DynamicDescriptionTool < Tool
      tool_name "dynamic_description_tool"
      
      description do |server_context|
        if server_context&.dig(:user, :role) == "admin"
          "Administrative tool with full access capabilities"
        else
          "User tool with limited read-only access"
        end
      end

      input_schema(properties: { action: { type: "string" } }, required: ["action"])

      class << self
        def call(action:, server_context: nil)
          role = server_context&.dig(:user, :role) || "user"
          Tool::Response.new([{ type: "text", text: "Action #{action} (#{role})" }])
        end
      end
    end

    # Static prompt for comparison
    class StaticPrompt < Prompt
      prompt_name "static_prompt"
      description "A prompt with static description"
      arguments []
      
      class << self
        def template(args, server_context: nil)
          Message.new(role: "user", content: "Static prompt with #{args}")
        end
      end
    end

    # Context-dependent prompt description
    class DynamicDescriptionPrompt < Prompt
      prompt_name "dynamic_description_prompt"
      arguments []
      
      description do |server_context|
        if server_context&.dig(:user, :premium)
          "Premium prompt with advanced features and customization"
        else
          "Basic prompt with standard functionality"
        end
      end

      class << self
        def template(args, server_context: nil)
          premium = server_context&.dig(:user, :premium)
          Message.new(role: "user", content: "#{premium ? 'Premium' : 'Basic'} prompt: #{args}")
        end
      end
    end

    test "static tool description behavior remains unchanged" do
      assert_equal "static_tool", StaticTool.name_value
      assert_equal "A tool with static description", StaticTool.description_value
      
      # Description should be the same regardless of context
      desc_no_context = StaticTool.description_value
      desc_with_context = StaticTool.description_value(server_context: { user: { role: "admin" } })
      
      assert_equal desc_no_context, desc_with_context
      assert_equal "A tool with static description", desc_no_context
    end

    test "dynamic tool generates different descriptions based on context" do
      # User description
      user_desc = DynamicDescriptionTool.description_value(server_context: { user: { role: "user" } })
      assert_equal "User tool with limited read-only access", user_desc
      
      # Admin description  
      admin_desc = DynamicDescriptionTool.description_value(server_context: { user: { role: "admin" } })
      assert_equal "Administrative tool with full access capabilities", admin_desc
      
      # No context (defaults to user)
      no_context_desc = DynamicDescriptionTool.description_value
      assert_equal "User tool with limited read-only access", no_context_desc
    end

    test "tool to_h includes context-resolved description" do
      # User context
      user_tool_h = DynamicDescriptionTool.to_h(server_context: { user: { role: "user" } })
      assert_equal "User tool with limited read-only access", user_tool_h[:description]
      
      # Admin context
      admin_tool_h = DynamicDescriptionTool.to_h(server_context: { user: { role: "admin" } })
      assert_equal "Administrative tool with full access capabilities", admin_tool_h[:description]
    end

    test "static prompt description behavior remains unchanged" do
      assert_equal "static_prompt", StaticPrompt.name_value
      assert_equal "A prompt with static description", StaticPrompt.description_value
      
      # Description should be the same regardless of context
      desc_no_context = StaticPrompt.description_value
      desc_with_context = StaticPrompt.description_value(server_context: { user: { premium: true } })
      
      assert_equal desc_no_context, desc_with_context
      assert_equal "A prompt with static description", desc_no_context
    end

    test "dynamic prompt generates different descriptions based on context" do
      # Basic user description
      basic_desc = DynamicDescriptionPrompt.description_value(server_context: { user: { premium: false } })
      assert_equal "Basic prompt with standard functionality", basic_desc
      
      # Premium user description
      premium_desc = DynamicDescriptionPrompt.description_value(server_context: { user: { premium: true } })
      assert_equal "Premium prompt with advanced features and customization", premium_desc
      
      # No context (defaults to basic)
      no_context_desc = DynamicDescriptionPrompt.description_value
      assert_equal "Basic prompt with standard functionality", no_context_desc
    end

    test "prompt to_h includes context-resolved description" do
      # Basic context
      basic_prompt_h = DynamicDescriptionPrompt.to_h(server_context: { user: { premium: false } })
      assert_equal "Basic prompt with standard functionality", basic_prompt_h[:description]
      
      # Premium context
      premium_prompt_h = DynamicDescriptionPrompt.to_h(server_context: { user: { premium: true } })
      assert_equal "Premium prompt with advanced features and customization", premium_prompt_h[:description]
    end

    test "server integration with context-dependent tool descriptions" do
      server = Server.new(
        name: "test_server",
        tools: [StaticTool, DynamicDescriptionTool],
        server_context: { user: { role: "admin" } }
      )

      # Test tools list includes context-resolved descriptions
      tools_list = server.send(:list_tools, {})

      static_tool_def = tools_list.find { |t| t[:name] == "static_tool" }
      dynamic_tool_def = tools_list.find { |t| t[:name] == "dynamic_description_tool" }

      # Static tool unchanged
      assert_equal "A tool with static description", static_tool_def[:description]

      # Dynamic tool should show admin description
      assert_equal "Administrative tool with full access capabilities", dynamic_tool_def[:description]
    end

    test "server integration with context-dependent prompt descriptions" do
      server = Server.new(
        name: "test_server",
        prompts: [StaticPrompt, DynamicDescriptionPrompt],
        server_context: { user: { premium: true } }
      )

      # Test prompts list includes context-resolved descriptions
      prompts_list = server.send(:list_prompts, {})

      static_prompt_def = prompts_list.find { |p| p[:name] == "static_prompt" }
      dynamic_prompt_def = prompts_list.find { |p| p[:name] == "dynamic_description_prompt" }

      # Static prompt unchanged
      assert_equal "A prompt with static description", static_prompt_def[:description]

      # Dynamic prompt should show premium description
      assert_equal "Premium prompt with advanced features and customization", dynamic_prompt_def[:description]
    end

    test "backward compatibility with existing static description declarations" do
      # Hash-based tool definition using define method
      hash_tool = Tool.define(
        name: "hash_tool",
        description: "A tool defined with hash syntax",
        input_schema: { properties: { msg: { type: "string" } }, required: ["msg"] }
      ) { |msg:| Tool::Response.new([{ type: "text", text: msg }]) }

      desc = hash_tool.description_value
      assert_equal "A tool defined with hash syntax", desc

      # Prompt definition
      hash_prompt = Prompt.define(
        name: "hash_prompt",
        description: "A prompt defined with hash syntax"
      ) { |args| Message.new(role: "user", content: args.to_s) }

      desc = hash_prompt.description_value  
      assert_equal "A prompt defined with hash syntax", desc
    end

    test "tool inheritance properly initializes description generator" do
      parent_tool = Class.new(Tool) do
        description { |_| "Parent tool description" }
      end

      child_tool = Class.new(parent_tool) do
        description { |_| "Child tool description" }
      end

      parent_desc = parent_tool.description_value(server_context: {})
      child_desc = child_tool.description_value(server_context: {})

      assert_equal "Parent tool description", parent_desc
      assert_equal "Child tool description", child_desc
    end

    test "prompt inheritance properly initializes description generator" do
      parent_prompt = Class.new(Prompt) do
        description { |_| "Parent prompt description" }
      end

      child_prompt = Class.new(parent_prompt) do
        description { |_| "Child prompt description" }
      end

      parent_desc = parent_prompt.description_value(server_context: {})
      child_desc = child_prompt.description_value(server_context: {})

      assert_equal "Parent prompt description", parent_desc
      assert_equal "Child prompt description", child_desc
    end

    test "description method supports both static values and blocks" do
      # Tool with static description
      static_tool = Class.new(Tool) do
        description "Static description"
      end
      assert_equal "Static description", static_tool.description_value

      # Tool with dynamic description
      dynamic_tool = Class.new(Tool) do
        description { |context| "Dynamic: #{context&.dig(:test)}" }
      end
      assert_equal "Dynamic: value", dynamic_tool.description_value(server_context: { test: "value" })

      # Prompt with static description
      static_prompt = Class.new(Prompt) do
        description "Static prompt description"
      end
      assert_equal "Static prompt description", static_prompt.description_value

      # Prompt with dynamic description  
      dynamic_prompt = Class.new(Prompt) do
        description { |context| "Dynamic prompt: #{context&.dig(:mode)}" }
      end
      assert_equal "Dynamic prompt: advanced", dynamic_prompt.description_value(server_context: { mode: "advanced" })
    end
  end
end
