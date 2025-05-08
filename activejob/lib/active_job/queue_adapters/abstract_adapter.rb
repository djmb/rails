# frozen_string_literal: true

module ActiveJob
  module QueueAdapters
    # = Active Job Abstract Adapter
    #
    # Active Job supports multiple job queue systems. ActiveJob::QueueAdapters::AbstractAdapter
    # forms the abstraction layer which makes this possible.
    class AbstractAdapter
      def enqueue(job)
        raise NotImplementedError
      end

      def enqueue_at(job, timestamp)
        raise NotImplementedError
      end

      def stopping?
        false
      end
    end
  end
end
