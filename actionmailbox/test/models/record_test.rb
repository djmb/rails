# frozen_string_literal: true

require "test_helper"

class ActionMailbox::RecordTest < ActiveSupport::TestCase
  test "superclass defaults to ActiveRecord::Base" do
    assert_equal ActiveRecord::Base, ActionMailbox::Record.superclass
  end
end
