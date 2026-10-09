class AddIgnoredGroupSuggestionsToTimeOffSchedules < ActiveRecord::Migration[7.1]
  def change
    add_column :time_off_schedules, :ignored_group_suggestions, :jsonb, default: [], null: false
  end
end
