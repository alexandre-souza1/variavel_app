class CreatePeopleCycleFeedbacks < ActiveRecord::Migration[7.1]
  def change
    create_table :people_cycle_feedbacks do |t|
      t.string :cycle, null: false
      t.string :employee_name, null: false
      t.string :employee_key, null: false
      t.string :stage, null: false
      t.text :response, null: false
      t.string :profile
      t.bigint :employee_id
      t.references :imported_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :people_cycle_feedbacks, [:cycle, :employee_key, :stage], unique: true, name: "index_people_feedback_unique"
    add_index :people_cycle_feedbacks, [:profile, :employee_id]
  end
end
