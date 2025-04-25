# frozen_string_literal: true

module ActiveJob
  class Continuation
    class Step
      attr_reader :name

      def initialize(continuation, name, cursor_wrapper)
        @continuation = continuation
        @name = name.to_sym
        @cursor_wrapper = cursor_wrapper
      end

      def checkpoint!(value = nil)
        cursor_wrapper.checkpoint(value)
        continuation.send(:checkpoint!, cursor)
      end

      def cursor
        cursor_wrapper.value
      end

      private
        attr_reader :continuation, :cursor_wrapper
    end
  end
end
