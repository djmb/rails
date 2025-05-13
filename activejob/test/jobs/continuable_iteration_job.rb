class ContinuableIterationJob < ActiveJob::Base
  include ActiveJob::Continuable

  cattr_accessor :items

  def perform
    step :rename do |step|
      counter = step.cursor || 0

      items[counter..]&.each do |item|
        items[counter] = "new_#{item}"
        step.checkpoint!(counter)

        counter += 1
      end
    end
  end
end