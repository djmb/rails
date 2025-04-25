# frozen_string_literal: true

require "helper"
require "jobs/continuing_iteration_job"
require "jobs/continuing_linear_job"
require "jobs/continuing_delete_job"
require "jobs/continuing_duplicate_step_job"
require "jobs/continuing_nested_cursor_job"

require "active_job/continuation/test_helper"
require "active_support/testing/stream"
require "active_support/core_ext/object/with"

class ActiveJob::TestContinuation < ActiveSupport::TestCase
  include ActiveJob::Continuation::TestHelper
  include ActiveSupport::Testing::Stream

  setup do
    @perform_enqueued_jobs = queue_adapter.perform_enqueued_jobs
    @perform_enqueued_at_jobs = queue_adapter.perform_enqueued_at_jobs
    queue_adapter.perform_enqueued_jobs = queue_adapter.perform_enqueued_at_jobs = false

    ContinuingLinearJob.items = []
    ContinuingIterationJob.items = 10.times.map { |i| "item_#{i}" }
    ContinuingDeleteJob.items = 10.times.map { |i| "item_#{i}" }
    ContinuingNestedCursorJob.nested_items = [3, 1, 2].map.with_index { |count, i| count.times.map { |j| "subitem_#{i}_#{j}" } }
  end

  teardown do
    queue_adapter.perform_enqueued_jobs = @perform_enqueued_jobs
    queue_adapter.perform_enqueued_at_jobs = @perform_enqueued_at_jobs
  end

  if adapter_is?(:test)
    test "iterates" do
      ContinuingIterationJob.perform_later

      assert_enqueued_jobs 0, only: ContinuingIterationJob do
        perform_enqueued_jobs
      end

      assert_equal %w[ new_item_0 new_item_1 new_item_2 new_item_3 new_item_4 new_item_5 new_item_6 new_item_7 new_item_8 new_item_9 ], ContinuingIterationJob.items
    end

    test "iterates and continues" do
      ContinuingIterationJob.perform_later

      interrupt_job_during_step ContinuingIterationJob, :rename, cursor: 4 do
        assert_enqueued_jobs 1, only: ContinuingIterationJob do
          perform_enqueued_jobs
        end
      end

      assert_equal %w[ new_item_0 new_item_1 new_item_2 new_item_3 item_4 item_5 item_6 item_7 item_8 item_9 ], ContinuingIterationJob.items

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal %w[ new_item_0 new_item_1 new_item_2 new_item_3 new_item_4 new_item_5 new_item_6 new_item_7 new_item_8 new_item_9 ], ContinuingIterationJob.items
    end

    test "linear steps" do
      ContinuingLinearJob.perform_later

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal %w[ item1 item2 item3 item4 ], ContinuingLinearJob.items
    end

    test "linear steps continues from last point" do
      ContinuingLinearJob.perform_later

      interrupt_job_after_step ContinuingLinearJob, :step_one do
        assert_enqueued_jobs 1, only: ContinuingLinearJob do
          perform_enqueued_jobs
        end
      end

      assert_equal %w[ item1 ], ContinuingLinearJob.items

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal %w[ item1 item2 item3 item4 ], ContinuingLinearJob.items
    end

    test "runs with perform_now" do
      ContinuingLinearJob.perform_now

      assert_equal %w[ item1 item2 item3 item4 ], ContinuingLinearJob.items
    end

    test "saves progress when there is an error" do
      ContinuingIterationJob.perform_later

      queue_adapter.with(stopping: ->() { raise StandardError if during_step?(ContinuingIterationJob, :rename, cursor: 4) }) do
        assert_enqueued_jobs 1, only: ContinuingIterationJob do
          perform_enqueued_jobs
        end
      end

      job = queue_adapter.enqueued_jobs.first
      assert_equal 1, job["executions"]

      assert_equal %w[ new_item_0 new_item_1 new_item_2 new_item_3 item_4 item_5 item_6 item_7 item_8 item_9 ], ContinuingIterationJob.items

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal %w[ new_item_0 new_item_1 new_item_2 new_item_3 new_item_4 new_item_5 new_item_6 new_item_7 new_item_8 new_item_9 ], ContinuingIterationJob.items
    end

    test "logs interruptions after steps" do
      ContinuingLinearJob.perform_later

      interrupt_job_after_step ContinuingLinearJob, :step_one do
        output = capture_info_stdout { perform_enqueued_jobs }
        assert_no_match("Resuming", output)
        assert_match(/Step 'step_one' started/, output)
        assert_match(/Step 'step_one' completed/, output)
        assert_match(/Interrupted ContinuingLinearJob \(Job ID: [0-9a-f-]{36}\) after 'step_one'/, output)
      end

      output = capture_info_stdout { perform_enqueued_jobs }
      assert_match(/Resuming ContinuingLinearJob \(Job ID: [0-9a-f-]{36}\) after 'step_one'/, output)
      assert_match(/Step 'step_two' started/, output)
      assert_match(/Step 'step_two' completed/, output)
    end

    test "logs interruptions during steps" do
      ContinuingIterationJob.perform_later

      interrupt_job_during_step ContinuingIterationJob, :rename, cursor: 2 do
        output = capture_info_stdout { perform_enqueued_jobs }
        assert_no_match("Resuming", output)
        assert_match(/Step 'rename' started/, output)
        assert_match(/Interrupted ContinuingIterationJob \(Job ID: [0-9a-f-]{36}\) at 'rename', cursor '2'/, output)
      end

      output = capture_info_stdout { perform_enqueued_jobs }
      assert_match(/Resuming ContinuingIterationJob \(Job ID: [0-9a-f-]{36}\) at 'rename', cursor '2'/, output)
      assert_match(/Step 'rename' resumed from cursor '2'/, output)
      assert_match(/Step 'rename' completed/, output)
    end

    test "interrupts without cursors" do
      ContinuingDeleteJob.perform_later

      interrupt_job_during_step ContinuingDeleteJob, :delete do
        assert_enqueued_jobs 1, only: ContinuingDeleteJob do
          perform_enqueued_jobs
        end
      end

      assert_equal 9, ContinuingDeleteJob.items.size

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal 0, ContinuingDeleteJob.items.size
    end

    test "duplicate steps raise an error" do
      ContinuingDuplicateStepJob.perform_later

      expection = assert_raises ActiveJob::Continuation::Error do
        perform_enqueued_jobs
      end

      assert_equal "Step 'duplicate' has already been encountered", expection.message
    end

    test "deserializes a job with no continuation" do
      ContinuingDeleteJob.perform_later

      queue_adapter.enqueued_jobs.each { |job| job.delete("continuation") }

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal 0, ContinuingDeleteJob.items.size
    end

    test "custom nested cursor" do
      ContinuingNestedCursorJob.perform_later

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal %w[ new_subitem_0_0 new_subitem_0_1 new_subitem_0_2 new_subitem_1_0 new_subitem_2_0 new_subitem_2_1 ], ContinuingNestedCursorJob.nested_items.flatten
    end

    test "custom nested cursor resumes" do
      ContinuingNestedCursorJob.perform_later

      interrupt_job_during_step ContinuingNestedCursorJob, :updating_sub_items, cursor: [ 0, 2 ] do
        assert_enqueued_jobs 1 do
          perform_enqueued_jobs
        end
      end

      assert_equal %w[ new_subitem_0_0 new_subitem_0_1 subitem_0_2 subitem_1_0 subitem_2_0 subitem_2_1 ], ContinuingNestedCursorJob.nested_items.flatten

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal %w[ new_subitem_0_0 new_subitem_0_1 new_subitem_0_2 new_subitem_1_0 new_subitem_2_0 new_subitem_2_1 ], ContinuingNestedCursorJob.nested_items.flatten
    end
  end

  private
    def capture_info_stdout
      ActiveJob::Base.with(logger: Logger.new(STDOUT)) do
        capture(:stdout) { yield }
      end
    end
end
