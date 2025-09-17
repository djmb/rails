# frozen_string_literal: true

class ActiveStorage::Record < ActiveStorage.record_base_class.constantize # :nodoc:
  self.abstract_class = true
end

ActiveSupport.run_load_hooks :active_storage_record, ActiveStorage::Record
