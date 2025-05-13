class ContinuableDeleteJob < ActiveJob::Base
  include ActiveJob::Continuable

  retry_on StandardError, wait: 0, attempts: 3

  cattr_accessor :items

  def perform
    step :delete do |step|
      loop do
        break if items.empty?
        items.pop
        step.checkpoint!
      end
    end
  end
end