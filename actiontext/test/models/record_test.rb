# frozen_string_literal: true

require "test_helper"

class ActionText::RecordTest < ActiveSupport::TestCase
  test "superclass defaults to ActiveRecord::Base" do
    assert_equal ActiveRecord::Base, ActionText::Record.superclass
  end
end
