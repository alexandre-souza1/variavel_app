class AddArchivedAtToActionPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :action_plans, :archived_at, :datetime
    add_index :action_plans, :archived_at
  end
end
