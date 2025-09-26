class CreateBudgetCategories < ActiveRecord::Migration[7.1]
  def change
    create_table :budget_categories do |t|
      t.string :name
      t.decimal :limit

      t.timestamps
    end
  end
end
