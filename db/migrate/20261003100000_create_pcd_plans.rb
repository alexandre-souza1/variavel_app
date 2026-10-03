class CreatePcdPlans < ActiveRecord::Migration[7.1]
  def change
    create_table :pcd_plans do |t|
      t.date :date, null: false
      t.jsonb :details, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :pcd_plans, :date, unique: true
    create_table :pcd_imports do |t|
      t.references :pcd_plan, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :filename, null: false
      t.string :digest, null: false
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    create_table :pcd_changes do |t|
      t.references :pcd_plan, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :action, null: false
      t.string :reason, null: false
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
  end
end
