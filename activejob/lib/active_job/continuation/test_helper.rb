# frozen_string_literal: true

require "active_job/test_helper"

module ActiveJob
  class Continuation
    module TestHelper
      include ::ActiveJob::TestHelper

      def interrupt_job_during_step(job, step, cursor: nil)
        queue_adapter.with(stopping: ->() { during_step?(job, step, cursor: cursor) }) do
          yield
        end
      end

      def interrupt_job_after_step(job, step)
        queue_adapter.with(stopping: ->() { after_step?(job, step) }) do
          yield
        end
      end

      private
        def continuation_for(klass)
          job = ActiveSupport::ExecutionContext.to_h[:job]
          job.send(:continuation) if job && job.is_a?(klass)
        end

        def during_step?(job, step, cursor: nil)
          progress = continuation_for(job)&.send(:progress)

          progress && progress.current && progress.current == step && progress.cursor == cursor
        end

        def after_step?(job, step)
          continuation = continuation_for(job)
          continuation && continuation.send(:progress).completed.last == step
        end
    end
  end
end
