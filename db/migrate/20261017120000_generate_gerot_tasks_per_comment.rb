class GenerateGerotTasksPerComment < ActiveRecord::Migration[7.1]
  def change
    remove_index :tasks, :routine_value_id, unique: true
    add_index :tasks, :routine_value_id
    add_reference :tasks, :routine_comment, index: { unique: true },
                  foreign_key: { on_delete: :nullify }
  end
end
