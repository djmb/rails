# frozen_string_literal: true

module ActiveJob
  class Continuation
    class Progress
      attr_reader :completed, :current, :cursor

      def initialize(serialized_progress)
        @completed, @current, @cursor = deserialize(serialized_progress)
        @advanced = false
      end

      def to_h
        serialize
      end

      def started?
        current.present? || completed.any?
      end

      def advanced?
        @advanced
      end

      def completed_step?(name)
        completed.include?(name)
      end

      def wrong_step?(name)
        !completed_step?(name) && current.present? && current != name
      end

      def description
        if current
          "at '#{current}', cursor '#{cursor}'"
        else
          "after '#{completed.last}'"
        end
      end

      def track(name, &block)
        with_current(name, &block)
        @completed << name
        @advanced = true
      end

      def cursor=(cursor)
        @advanced = true if cursor != @cursor
        @cursor = cursor
      end

      private
        def serialize
          {
            "completed" => completed.map(&:to_s),
            "current" => current&.to_s,
            "cursor" => cursor
          }.compact
        end

        def deserialize(serialized_progress)
          [
            serialized_progress.fetch("completed", []).map(&:to_sym),
            serialized_progress["current"]&.to_sym,
            serialized_progress["cursor"]
          ]
        end

        def with_current(name, &block)
          @current = name
          block.call
          @current = nil
        end
    end
  end
end
