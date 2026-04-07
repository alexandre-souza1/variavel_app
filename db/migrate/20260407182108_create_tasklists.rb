class CreateTasklists < ActiveRecord::Migration[7.1]
  def change
    create_table :tasklists do |t|
      t.string :title
      t.references :task, null: false, foreign_key: true

      t.timestamps
    end
  end
end
