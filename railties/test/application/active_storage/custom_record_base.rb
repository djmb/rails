# frozen_string_literal: true

require "isolation/abstract_unit"

module ApplicationTests
  class ActiveStorageCustomRecordTest < ActiveSupport::TestCase
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
        config.active_storage.record_base_class = "ApplicationRecord"
      RUBY

      rails "active_storage:install"
      rails "db:migrate"

      require "#{app_path}/config/environment"
      assert_equal ApplicationRecord, ActiveStorage::Record.superclass
    end
  end
end
