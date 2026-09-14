class AddPublicToActionPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :action_plans, :public, :boolean, null: false, default: true
  end
end
