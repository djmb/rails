# frozen_string_literal: true

require "test_helper"
require "database/setup"

class ActiveStorage::RecordTest < ActiveSupport::TestCase
  test "superclass defaults to ActiveRecord::Base" do
    assert_equal ActiveRecord::Base, ActiveStorage::Record.superclass
  end
end
