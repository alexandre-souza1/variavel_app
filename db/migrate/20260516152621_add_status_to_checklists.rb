class AddStatusToChecklists < ActiveRecord::Migration[7.1]
  def change
    add_column :checklists, :status, :string, default: "draft"
  end
end