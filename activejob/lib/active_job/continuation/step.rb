# frozen_string_literal: true

module ActiveJob
  class Continuation
    # = Active Job Continuation Step
    #
    # Represents a single step within a job continuation.
    class Step
      # The name of the step (as a symbol).
      attr_reader :name

      def initialize(continuation, name, cursor_wrapper)
        @continuation = continuation
        @name = name.to_sym
        @cursor_wrapper = cursor_wrapper
      end

      # Records a checkpoint within the current step. This saves the current
      # cursor value and checks if we should interrupt the job.
      def checkpoint!(value = nil)
        cursor_wrapper.checkpoint(value)
        continuation.send(:checkpoint!, cursor)
      end

      # Returns the current cursor value, which represents the progress within this step.
      def cursor
        cursor_wrapper.value
      end

      private
        attr_reader :continuation, :cursor_wrapper
    end
  end
end
