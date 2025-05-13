ContinuableNestedCursor = ActiveJob::Continuation::Cursor.build \
  default: -> { [] },
  validate: ->(value) { raise "Cursor value must be an array of Integers" unless value.is_a?(Array) && value.all?(Integer) },
  advance: ->(value) { value.empty? ? value : value[0..-2] + [ value.last + 1 ] }

class ContinuableNestedCursorJob < ActiveJob::Base
  include ActiveJob::Continuable

  cattr_accessor :nested_items

  def perform
    step :updating_sub_items, cursor_type: ContinuableNestedCursor do |step|
      outer_counter = step.cursor[0] || 0

      nested_items[outer_counter..].each do |items|
        inner_counter = step.cursor[1] || 0

        items[inner_counter..].each do |item|
          items[inner_counter] = "new_#{item}"

          step.checkpoint! [ outer_counter, inner_counter ]
          inner_counter = step.cursor[1]
        end

        step.checkpoint! [ outer_counter ]
        outer_counter = step.cursor[0]
      end
    end
  end
end