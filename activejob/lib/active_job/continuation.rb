# frozen_string_literal: true

require "active_job/continuing"
require "active_job/continuation/cursor"
require "active_job/continuation/progress"
require "active_job/continuation/step"

module ActiveJob
  class Continuation
    class Interrupt < Exception; end
    class Error < StandardError; end
    class InvalidStepError < Error; end
    class InvalidCursorError < Error; end
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
