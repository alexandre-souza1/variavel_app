class AddChecklistTrackingVisibilityToActionPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :action_plans, :checklist_tracking_visible, :boolean, null: false, default: true
  end
end
