# frozen_string_literal: true

require "active_job/continuable"
require "active_job/continuation/cursor"
require "active_job/continuation/progress"
require "active_job/continuation/step"

module ActiveJob
  # = Active Job Continuation
  #
  # Continuations provide a mechanism for interrupting and resuming jobs. This allows
  # long running jobs to make progress across application restarts.
  #
  # Jobs should include the [ActiveJob::Continuable] module to enable continuations.
  #
  # Use the `step` method to define the steps in your job. Steps can use an optional
  # cursor to track progress in the step.
  #
  # You can pass a block to the step method:
  #
  #   class ProcessImportJob < ApplicationJob
  #     include ActiveJob::Continuable
  #
  #     def perform(import_id)
  #       import = Import.find(import_id)
  #
  #       step(:validate) { import.validate! }
  #
  #       step(:process_records) do |step|
  #         import.records.find_each(start: step.cursor)
  #           record.process
  #           step.checkpoint!(record.id)
  #         end
  #       end
  #
  #       step(:finalize) { import.finalize! }
  #     end
  #   end
  #
  # Or if you don't want to use a block, you can define a method with the same name as the step.
  # The method can either take no arguments or a single argument for the step object.
  #
  #   class ProcessImportJob < ApplicationJob
  #     include ActiveJob::Continuable
  #
  #     def perform(import_id)
  #       @import = Import.find(import_id)
  #
  #       step :validate
  #       step :process_records
  #       step :finalize
  #     end
  #
  #     private
  #       def validate
  #         @import.validate!
  #       end
  #
  #       def process_records(step)
  #         @import.records.find_each(start: step.cursor) do |record|
  #           record.process
  #           step.checkpoint!(record.id)
  #         end
  #       end
  #
  #       def finalize
  #         @import.finalize!
  #       end
  #   end
  #
  # === Cursors
  #
  # Cursors are used to track progress in a step. The default cursor is ActiveJob:Continuation::OffsetCursor.
  #
  # Each cursor wraps a cursor value. The step.cursor method returns the wrapped value.
  # When calling step.checkpoint!(value) you provide a checkpoint value for the work you have just completed.
  #
  # You define a new cursor by calling ActiveJob::Continuation::Cursor.build, which returns a new
  # cursor class that inherits from ActiveJob::Continuation::Cursor.
  #
  # Here's how OffsetCursor is defined:
  #
  #   ActiveJob::Continuation::Cursor.build /
  #     default: ->() { nil },
  #     validate: ->(value) { raise "Cursor value must be an integer or nil" unless value.nil? || value.is_a?(Integer) },
  #     advance: ->(value) { value + 1 }
  #
  # When the checkpoint! method is called, the cursor value is validated and then advanced.
  #
  # See the ActiveJob::Continuation::Cursor class for more information on how to define custom cursors.
  #
  # You might want checkpoint your work, but not need to track progress. For example if you are looping through records
  # and destroying them.
  #
  # You can just call checkpoint! with no value to do this:
  #
  #   step(:destroy_records) do |step|
  #     @import.records.find_each do |record|
  #       record.destroy
  #       step.checkpoint!
  #     end
  #   end
  #
  # There are implicit checkpoints at the end of each step that record that the step completed. Manual checkpoints are optional
  # and are only needed if you want to track progress or interrupt the job within a step.
  #
  # === Interrupting and Resuming Jobs
  #
  # It is the job's responsibility to check whether it should be interrupted.
  #
  # It will check at two points:
  # * When a step completes
  # * When the checkpoint! method is called on a step.
  #
  # The job checks whether it should be interrupted, by calling the `stopping?` method
  # on the queue adapter.
  #
  # If the queue adapter is stopping, the job will raise an ActiveJob::Continuation::Interrupt exception.
  # This is an Exception, not a StandardError. It should not be rescued by the job.
  #
  # The job with be requeued for a retry with its progress serialized under the "continuation" key.
  # The serialized progress contains a list of the completed steps, and the current step and its cursor value
  # if one is in progress.
  class Continuation
    # Raised when a job is interrupted and needs to be resumed later
    class Interrupt < Exception; end

    # Base class for all continuation-related errors
    class Error < StandardError; end

    # Raised when a step is invalid
    class InvalidStepError < Error; end

    # Raised when an invalid cursor value is provided
    class InvalidCursorError < Error; end

    # Raised when a job advances and then raised a StandardError that is not a ActiveJob::Continuation::Error.
    # The job will be automatically retried to ensure that the progress is serialized in the retried job.
    class AdvancedWithError < Error; end

    delegate :description, :advanced?, :to_h, to: :progress

    def initialize(job, progress)
      @job = job
      @progress = Progress.new(progress)
      @encountered = []
      @resuming = @progress.started?
    end

    def continue(&block)
      instrument :resume, progress: progress if resuming?
      block.call
    rescue StandardError => e
      if advanced? && !e.is_a?(Error)
        raise AdvancedWithError, "Job advanced, then failed with error: #{e.message}", cause: e
      else
        raise
      end
    end

    def step(name, cursor_type:, &block)
      ensure_valid_step(name)

      encountered << name

      if progress.completed_step?(name)
        skip_step(name)
      else
        run_step(name, cursor_type: cursor_type || OffsetCursor, &block)
      end
    end

    private
      attr_reader :job, :progress, :encountered, :running_step, :resuming
      alias_method :resuming?, :resuming

      def ensure_valid_step(name)
        raise InvalidStepError, "Step '#{name}' must be a symbol" unless name.is_a?(Symbol)
        raise InvalidStepError, "Step '#{name}' has already been encountered" if encountered.include?(name)
        raise InvalidStepError, "Step '#{name}' is nested inside step '#{progress.current}'" if running_step
        raise InvalidStepError, "Step '#{name}' found, expected to resume from '#{progress.current}'" if progress.wrong_step?(name)
      end

      def skip_step(name)
        instrument :step_skipped, step: name
      end

      def run_step(name, cursor_type:, &block)
        @running_step = true

        instrument_step(name) do
          progress.track(name) do
            block.call(Step.new(self, name, cursor_type.new(progress.cursor)))
          end
        end
        @running_step = false

        checkpoint!
      end

      def instrument_step(name)
        if progress.current
          instrument :step_resumed, step: name, cursor: progress.cursor
        else
          instrument :step_started, step: name
        end

        yield

        instrument :step_completed, step: name
      end

      def instrument(name, payload = {})
        job.send(:instrument, name, payload.merge(job: job))
      end

      def interrupt!
        instrument :interrupt, progress: progress
        raise Interrupt, "Interrupted #{description}"
      end

      def checkpoint!(value = nil)
        progress.cursor = value

        interrupt! if job.queue_adapter.stopping?
      end
  end
end
