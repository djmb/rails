# frozen_string_literal: true

require "isolation/abstract_unit"

module ApplicationTests
  class ActionMailboxTest < ActiveSupport::TestCase
    include ActiveSupport::Testing::Isolation

    def setup
      build_app
    end

    def teardown
      teardown_app
    end

    def test_application_record_as_record_base
      add_to_config <<-RUBY
        config.root = "#{app_path}"
        config.action_mailbox.record_base_class = "ApplicationRecord"
      RUBY

      rails "action_mailbox:install"

      require "#{app_path}/config/environment"
      assert_equal ApplicationRecord, ActionMailbox::Record.superclass
    end
  end
end
