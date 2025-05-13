# frozen_string_literal: true

module ActiveJob
  class Continuation
    # = Active Job Continuation Cursor
    #
    # Cursors track the progress within a specific step. They can be
    # built with custom validation and advancement logic.
    #
    # The default cursor is OffsetCursor, which uses integer values
    # and increments by 1 with each advancement.
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
