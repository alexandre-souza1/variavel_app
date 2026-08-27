class CreateInvoiceGoals < ActiveRecord::Migration[7.1]
  def change
    create_table :invoice_goals do |t|
      t.string :name, null: false
      t.string :sector, null: false
      t.date :reference_month, null: false
      t.decimal :target_amount, precision: 15, scale: 2, null: false

      t.timestamps
    end

    add_index :invoice_goals, [:sector, :reference_month, :name], unique: true

    create_table :invoice_goal_categories do |t|
      t.references :invoice_goal, null: false, foreign_key: true
      t.references :budget_category, null: false, foreign_key: true

      t.timestamps
    end

    add_index :invoice_goal_categories,
              [:invoice_goal_id, :budget_category_id],
              unique: true,
              name: "index_invoice_goal_categories_on_goal_and_category"
  end
end
