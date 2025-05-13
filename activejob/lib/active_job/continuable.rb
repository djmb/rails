# frozen_string_literal: true

module ActiveJob
  # = Active Job Continuable
  #
  # Continuable provides a mechanism for jobs to be broken down into steps
  # that can be interrupted and resumed. This allows long-running jobs
  # to make incremental progress, and ensures they can recover automatically
  # from transient failures without repeating completed work.
  #
  # Include this module in your job class to enable continuations:
  #
  #   class ProcessImportJob < ApplicationJob
  #     include ActiveJob::Continuable
  #
  #     def perform(import_id)
  #       import = Import.find(import_id)
  #
  #       step(:validate) { import.validate! }
  #
  #       step(:process_records) do |s|
  #         import.records.each_with_index do |record, i|
  #           next if i < s.cursor
  #           process_record(record)
  #           s.checkpoint!(i)
  #         end
  #       end
  #
  #       step(:finalize) { import.finalize! }
  #     end
  #   end
  #
  # If the job is interrupted during execution (for example, by a worker
  # shutdown), it will automatically be retried and resumed from where it left off.
  module Continuable
    extend ActiveSupport::Concern

    CONTINUATION_KEY = "continuation"

    included do
      retry_on Continuation::Interrupt, Continuation::AdvancedWithError, wait: 0, attempts: :unlimited

      around_perform :continue
    end

    # Executes a step in the job process, with automatic state tracking and resumption.
    #
    # When a block is not provided, the method calls a method with the same name as the step:
    #
    #   def perform
    #     step(:process_data)  # Will call the `process_data` method
    #   end
    #
    #   def process_data(step)
    #     # Step implementation that receives the step object
    #   end
    #
    # The step method can either take no arguments or a single argument for the step object.
    def step(step_name, cursor_type: nil, &block)
      continuation.step(step_name, cursor_type: cursor_type) do |step|
        if block_given?
          block.call(step)
        else
          step_method = method(step_name)

          raise ArgumentError, "Step method '#{step_name}' must accept 0 or 1 arguments" if step_method.arity > 1

          if step_method.parameters.any? { |type, name| type == :key || type == :keyreq }
            raise ArgumentError, "Step method '#{step_name}' must not accept keyword arguments"
          end

          step_method.arity == 0 ? step_method.call : step_method.call(step)
        end
      end
    end

    # Serializes the job, including the continuation state.
    def serialize
      super.merge(CONTINUATION_KEY => continuation.to_h)
    end

    # Deserializes the job and restores the continuation state.
    def deserialize(job_data)
      super
      @continuation = Continuation.new(self, job_data.fetch(CONTINUATION_KEY, {}))
    end

    private
      def continuation
        @continuation ||= Continuation.new(self, {})
      end

      def continue(&block)
        continuation.continue(&block)
      end
  end
end