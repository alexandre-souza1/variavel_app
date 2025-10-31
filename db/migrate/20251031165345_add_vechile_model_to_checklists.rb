class AddVechileModelToChecklists < ActiveRecord::Migration[7.1]
  def change
    add_column :checklists, :vechile_model, :string
  end
end
