class AddOnDeleteCascadeToTasklists < ActiveRecord::Migration[7.1]
  def change
    remove_foreign_key :tasklists, :tasks
    add_foreign_key :tasklists, :tasks, on_delete: :cascade
  end
end
