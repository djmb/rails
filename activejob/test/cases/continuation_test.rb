# frozen_string_literal: true

require "helper"
require "jobs/continuable_iteration_job"
require "jobs/continuable_linear_job"
require "jobs/continuable_delete_job"
require "jobs/continuable_duplicate_step_job"
require "jobs/continuable_nested_cursor_job"

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

    ContinuableLinearJob.items = []
    ContinuableIterationJob.items = 10.times.map { |i| "item_#{i}" }
    ContinuableDeleteJob.items = 10.times.map { |i| "item_#{i}" }
    ContinuableNestedCursorJob.nested_items = [3, 1, 2].map.with_index { |count, i| count.times.map { |j| "subitem_#{i}_#{j}" } }
  end

  teardown do
    queue_adapter.perform_enqueued_jobs = @perform_enqueued_jobs
    queue_adapter.perform_enqueued_at_jobs = @perform_enqueued_at_jobs
  end

  if adapter_is?(:test)
    test "iterates" do
      ContinuableIterationJob.perform_later

      assert_enqueued_jobs 0, only: ContinuableIterationJob do
        perform_enqueued_jobs
      end

      assert_equal %w[ new_item_0 new_item_1 new_item_2 new_item_3 new_item_4 new_item_5 new_item_6 new_item_7 new_item_8 new_item_9 ], ContinuableIterationJob.items
    end

    test "iterates and continues" do
      ContinuableIterationJob.perform_later

      interrupt_job_during_step ContinuableIterationJob, :rename, cursor: 4 do
        assert_enqueued_jobs 1, only: ContinuableIterationJob do
          perform_enqueued_jobs
        end
      end

      assert_equal %w[ new_item_0 new_item_1 new_item_2 new_item_3 item_4 item_5 item_6 item_7 item_8 item_9 ], ContinuableIterationJob.items

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal %w[ new_item_0 new_item_1 new_item_2 new_item_3 new_item_4 new_item_5 new_item_6 new_item_7 new_item_8 new_item_9 ], ContinuableIterationJob.items
    end

    test "linear steps" do
      ContinuableLinearJob.perform_later

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal %w[ item1 item2 item3 item4 ], ContinuableLinearJob.items
    end

    test "linear steps continues from last point" do
      ContinuableLinearJob.perform_later

      interrupt_job_after_step ContinuableLinearJob, :step_one do
        assert_enqueued_jobs 1, only: ContinuableLinearJob do
          perform_enqueued_jobs
        end
      end

      assert_equal %w[ item1 ], ContinuableLinearJob.items

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal %w[ item1 item2 item3 item4 ], ContinuableLinearJob.items
    end

    test "runs with perform_now" do
      ContinuableLinearJob.perform_now

      assert_equal %w[ item1 item2 item3 item4 ], ContinuableLinearJob.items
    end

    test "saves progress when there is an error" do
      ContinuableIterationJob.perform_later

      queue_adapter.with(stopping: ->() { raise StandardError if during_step?(ContinuableIterationJob, :rename, cursor: 4) }) do
        assert_enqueued_jobs 1, only: ContinuableIterationJob do
          perform_enqueued_jobs
        end
      end

      job = queue_adapter.enqueued_jobs.first
      assert_equal 1, job["executions"]

      assert_equal %w[ new_item_0 new_item_1 new_item_2 new_item_3 item_4 item_5 item_6 item_7 item_8 item_9 ], ContinuableIterationJob.items

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal %w[ new_item_0 new_item_1 new_item_2 new_item_3 new_item_4 new_item_5 new_item_6 new_item_7 new_item_8 new_item_9 ], ContinuableIterationJob.items
    end

    test "logs interruptions after steps" do
      ContinuableLinearJob.perform_later

      interrupt_job_after_step ContinuableLinearJob, :step_one do
        output = capture_info_stdout { perform_enqueued_jobs }
        assert_no_match("Resuming", output)
        assert_match(/Step 'step_one' started/, output)
        assert_match(/Step 'step_one' completed/, output)
        assert_match(/Interrupted ContinuableLinearJob \(Job ID: [0-9a-f-]{36}\) after 'step_one'/, output)
      end

      output = capture_info_stdout { perform_enqueued_jobs }
      assert_match(/Resuming ContinuableLinearJob \(Job ID: [0-9a-f-]{36}\) after 'step_one'/, output)
      assert_match(/Step 'step_two' started/, output)
      assert_match(/Step 'step_two' completed/, output)
    end

    test "logs interruptions during steps" do
      ContinuableIterationJob.perform_later

      interrupt_job_during_step ContinuableIterationJob, :rename, cursor: 2 do
        output = capture_info_stdout { perform_enqueued_jobs }
        assert_no_match("Resuming", output)
        assert_match(/Step 'rename' started/, output)
        assert_match(/Interrupted ContinuableIterationJob \(Job ID: [0-9a-f-]{36}\) at 'rename', cursor '2'/, output)
      end

      output = capture_info_stdout { perform_enqueued_jobs }
      assert_match(/Resuming ContinuableIterationJob \(Job ID: [0-9a-f-]{36}\) at 'rename', cursor '2'/, output)
      assert_match(/Step 'rename' resumed from cursor '2'/, output)
      assert_match(/Step 'rename' completed/, output)
    end

    test "interrupts without cursors" do
      ContinuableDeleteJob.perform_later

      interrupt_job_during_step ContinuableDeleteJob, :delete do
        assert_enqueued_jobs 1, only: ContinuableDeleteJob do
          perform_enqueued_jobs
        end
      end

      assert_equal 9, ContinuableDeleteJob.items.size

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal 0, ContinuableDeleteJob.items.size
    end

    test "duplicate steps raise an error" do
      ContinuableDuplicateStepJob.perform_later

      expection = assert_raises ActiveJob::Continuation::Error do
        perform_enqueued_jobs
      end

      assert_equal "Step 'duplicate' has already been encountered", expection.message
    end

    test "deserializes a job with no continuation" do
      ContinuableDeleteJob.perform_later

      queue_adapter.enqueued_jobs.each { |job| job.delete("continuation") }

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal 0, ContinuableDeleteJob.items.size
    end

    test "custom nested cursor" do
      ContinuableNestedCursorJob.perform_later

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal %w[ new_subitem_0_0 new_subitem_0_1 new_subitem_0_2 new_subitem_1_0 new_subitem_2_0 new_subitem_2_1 ], ContinuableNestedCursorJob.nested_items.flatten
    end

    test "custom nested cursor resumes" do
      ContinuableNestedCursorJob.perform_later

      interrupt_job_during_step ContinuableNestedCursorJob, :updating_sub_items, cursor: [ 0, 2 ] do
        assert_enqueued_jobs 1 do
          perform_enqueued_jobs
        end
      end

      assert_equal %w[ new_subitem_0_0 new_subitem_0_1 subitem_0_2 subitem_1_0 subitem_2_0 subitem_2_1 ], ContinuableNestedCursorJob.nested_items.flatten

      assert_enqueued_jobs 0 do
        perform_enqueued_jobs
      end

      assert_equal %w[ new_subitem_0_0 new_subitem_0_1 new_subitem_0_2 new_subitem_1_0 new_subitem_2_0 new_subitem_2_1 ], ContinuableNestedCursorJob.nested_items.flatten
    end
  end

  private
    def capture_info_stdout
      ActiveJob::Base.with(logger: Logger.new(STDOUT)) do
        capture(:stdout) { yield }
      end
    end
end
