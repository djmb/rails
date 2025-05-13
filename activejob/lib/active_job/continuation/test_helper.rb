# frozen_string_literal: true

require "active_job/test_helper"

module ActiveJob
  class Continuation
    # = Active Job Continuation Test Helper
    #
    # Provides methods to help test job continuations by simulating
    # interruptions at specific points during job execution.
    #
    # Include this module in your test class to gain access to methods
    # for interrupting jobs at specific steps or cursor positions.
    #
    # Example:
    #
    #   class MyJobTest < ActiveJob::TestCase
    #     include ActiveJob::Continuation::TestHelper
    #
    #     test "job can be interrupted and resumed" do
    #       # First run will be interrupted during :process_data step
    #       interrupt_job_during_step(MyJob, :process_data) do
    #         MyJob.perform_later(42)
    #         assert_enqueued_jobs 1
    #       end
    #
    #       # Next run will complete
    #       perform_enqueued_jobs
    #       assert_performed_jobs 2 # Initial + resumed run
    #     end
    #   end
    module TestHelper
      include ::ActiveJob::TestHelper

      # Interrupts a job's execution when it reaches a specific step and cursor position.
      #
      # Used in tests to simulate job interruption at specific points during execution.
      def interrupt_job_during_step(job, step, cursor: nil)
        queue_adapter.with(stopping: ->() { during_step?(job, step, cursor: cursor) }) do
          yield
        end
      end

      # Interrupts a job's execution immediately after a specific step completes.
      #
      # Used in tests to simulate job interruption after a step finishes.
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
