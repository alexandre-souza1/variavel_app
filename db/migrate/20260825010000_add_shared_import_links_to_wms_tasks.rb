class AddSharedImportLinksToWmsTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :wms_tasks, :source_key, :string
    add_reference :wms_tasks, :az_rv_import, foreign_key: true

    add_index :wms_tasks, :source_key, unique: true, where: "source_key IS NOT NULL"
  end
end
