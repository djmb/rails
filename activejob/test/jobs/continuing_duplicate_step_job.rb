class ContinuingDuplicateStepJob < ActiveJob::Base
  include ActiveJob::Continuing

  def perform
    step :duplicate do |step|
    end
    step :duplicate do |step|
    end
  end
end
