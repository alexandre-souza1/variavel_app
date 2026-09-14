class CreateHiddenActionPlans < ActiveRecord::Migration[7.1]
  def change
    create_table :hidden_action_plans do |t|
      t.references :user, null: false, foreign_key: true
      t.references :action_plan, null: false, foreign_key: true

      t.timestamps
    end

    add_index :hidden_action_plans, [:user_id, :action_plan_id], unique: true
  end
end
