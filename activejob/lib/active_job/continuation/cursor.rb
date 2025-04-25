# frozen_string_literal: true

module ActiveJob
  class Continuation
    class Cursor
      attr_reader :value

      class << self
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
