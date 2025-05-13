# frozen_string_literal: true

module ActiveJob
  class Continuation
    # = Active Job Continuation Step
    #
    # Represents a single step within a job continuation. Each step has a name
    # and maintains its own cursor position for tracking progress within the step.
    #
    # This class is used internally by the continuation system and is exposed to
    # job implementations through the step block parameter.
    class Step
      # The name of the step (as a symbol).
      attr_reader :name

      def initialize(continuation, name, cursor_wrapper)
        @continuation = continuation
        @name = name.to_sym
        @cursor_wrapper = cursor_wrapper
      end

      # Records a checkpoint within the current step. This saves the current
      # position and will allow the job to resume from this point if interrupted.
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
