# frozen_string_literal: true

module ActionMailbox
  class Record < ActionMailbox.record_base_class.constantize # :nodoc:
    self.abstract_class = true
  end
end

ActiveSupport.run_load_hooks :action_mailbox_record, ActionMailbox::Record
