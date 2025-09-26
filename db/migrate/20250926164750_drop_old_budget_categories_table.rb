class DropOldBudgetCategoriesTable < ActiveRecord::Migration[7.1]
  def up
    drop_table :budget_categories, if_exists: true
  end

  def down
    # Se precisar reverter, recria a tabela (mas provavelmente não será necessário)
    create_table :budget_categories do |t|
      t.string :name
      t.timestamps
    end
  end
end
