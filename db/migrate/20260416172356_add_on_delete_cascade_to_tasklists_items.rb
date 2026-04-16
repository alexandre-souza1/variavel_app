class AddOnDeleteCascadeToTasklistsItems < ActiveRecord::Migration[7.1]
  def change
    remove_foreign_key :tasklist_items, :tasklists
    add_foreign_key :tasklist_items, :tasklists, on_delete: :cascade
  end
end
