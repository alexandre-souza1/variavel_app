class AddSelectedIndicatorIdsToRoutines < ActiveRecord::Migration[7.1]
  def change
    add_column :routines, :selected_indicator_ids, :jsonb, default: [], null: false
  end
end
