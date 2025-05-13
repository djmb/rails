# frozen_string_literal: true

module ActiveJob
  class Continuation
    # = Active Job Continuation Cursor
    #
    # The default cursor is OffsetCursor, which uses integer values.
    #
    # You can create custom cursor classes calling +Cursor.build+
    #
    # === Example
    #
    # NestedOffsetCursor shows how to create a cursor that we can use to track progress in nested loops.
    #
    #   NestedOffsetCursor = Cursor.build \
    #     default: ->() { [] },
    #     validate: ->(value) { raise "Cursor value must be an array of Integers" unless value.is_a?(Array) && value.all?(Integer) },
    #     advance: ->(value) { value.empty? ? value : value[0..-2] + [ value.last + 1 ] }
    #
    # You can use this cursor by passing +cursor_type: NestedOffsetCursor+ to the step method:
    #
    #   class ProcessImportJob < ApplicationJob
    #     include ActiveJob::Continuable
    #
    #     def perform
    #       import = Import.find(import_id)
    #
    #       step :process_records, cursor_type: NestedOffsetCursor do |step|
    #         import.outer_records.find_each(start: step.cursor[0]) do |outer_record|
    #           outer_record.inner_records.find_each(start: step.cursor[1]) do |inner_record|
    #             inner_record.process
    #             step.checkpoint! [ outer_record.id, inner_record.id ]
    #           end
    #           step.checkpoint! [ outer_record.id ]
    #         end
    #       end
    #     end
    #   end
    #
    class Cursor
      # The current value of the cursor
      attr_reader :value

      class << self
        # Creates a new cursor class with specific behavior.
        #
        # Creates and returns a new Cursor subclass with custom behavior for tracking position
        # within a step.
        def build(default: -> { nil }, validate:, advance:)
          Class.new(self) do
            private define_method(:default, &default)
            private define_method(:validate_original, &validate)
            private define_method(:advance, &advance)
          end
        end
      end

      def initialize(value)
        if value.nil?
          @value = default
        else
          validate(value)
          @value = value
        end
      end

      # Updates the cursor value based on a checkpoint.
      #
      # Raises InvalidCursorError if the value is invalid.
      def checkpoint(value)
        if value.nil?
          @value = default
        else
          validate(value)
          @value = advance(value)
        end
      end

      private
        def validate(value)
          validate_original(value)
        rescue => error
          raise InvalidCursorError, "Invalid cursor value: #{value.inspect}, #{error.message}"
        end
    end

    OffsetCursor = Cursor.build \
      validate: ->(value) { raise "Cursor value must be an integer or nil" unless value.nil? || value.is_a?(Integer) },
      advance: ->(value) { value + 1 }
  end
end
