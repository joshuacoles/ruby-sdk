# frozen_string_literal: true

module MCP
  class Tool
    class << self
      NOT_SET = Object.new

      attr_reader :title_value
      attr_reader :description_value
      attr_reader :annotations_value

      def call(*args, server_context: nil)
        raise NotImplementedError, "Subclasses must implement call"
      end

      def to_h(server_context: nil)
        result = {
          name: name_value,
          title: title_value,
          description: description_value,
          inputSchema: input_schema_value(server_context: server_context).to_h,
        }
        result[:annotations] = annotations_value.to_h if annotations_value
        result
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@name_value, nil)
        subclass.instance_variable_set(:@title_value, nil)
        subclass.instance_variable_set(:@description_value, nil)
        subclass.instance_variable_set(:@input_schema_value, nil)
        subclass.instance_variable_set(:@input_schema_generator, nil)
        subclass.instance_variable_set(:@annotations_value, nil)
      end

      def tool_name(value = NOT_SET)
        if value == NOT_SET
          name_value
        else
          @name_value = value
        end
      end

      def name_value
        @name_value || StringUtils.handle_from_class_name(name)
      end

      def input_schema_value(server_context: nil)
        if @input_schema_generator
          schema_def = @input_schema_generator.call(server_context)
          if schema_def.is_a?(Hash)
            properties = schema_def[:properties] || schema_def["properties"] || {}
            required = schema_def[:required] || schema_def["required"] || []
            InputSchema.new(properties:, required:)
          elsif schema_def.is_a?(InputSchema)
            schema_def
          else
            raise ArgumentError, "Schema generator must return Hash or InputSchema, got #{schema_def.class}"
          end
        else
          @input_schema_value || InputSchema.new
        end
      end

      def title(value = NOT_SET)
        if value == NOT_SET
          @title_value
        else
          @title_value = value
        end
      end

      def description(value = NOT_SET)
        if value == NOT_SET
          @description_value
        else
          @description_value = value
        end
      end

      def input_schema(value = NOT_SET, &block)
        if value == NOT_SET && !block
          input_schema_value
        elsif block
          @input_schema_generator = block
        elsif value.is_a?(Hash)
          properties = value[:properties] || value["properties"] || {}
          required = value[:required] || value["required"] || []
          @input_schema_value = InputSchema.new(properties:, required:)
        elsif value.is_a?(InputSchema)
          @input_schema_value = value
        end
      end

      def annotations(hash = NOT_SET)
        if hash == NOT_SET
          @annotations_value
        else
          @annotations_value = Annotations.new(**hash)
        end
      end

      def define(name: nil, title: nil, description: nil, input_schema: nil, annotations: nil, &block)
        Class.new(self) do
          tool_name name
          title title
          description description
          input_schema input_schema
          self.annotations(annotations) if annotations
          define_singleton_method(:call, &block) if block
        end
      end
    end
  end
end
