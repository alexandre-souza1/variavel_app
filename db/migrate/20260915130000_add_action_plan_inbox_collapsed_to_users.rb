class AddActionPlanInboxCollapsedToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :action_plan_inbox_collapsed, :boolean, default: false, null: false
  end
end
