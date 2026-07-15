class ChangeChecklistPlateForeignKey < ActiveRecord::Migration[7.1]
  def change
    remove_foreign_key :checklists, :plates

    add_foreign_key :checklists,
                    :plates,
                    on_delete: :nullify
  end
end
