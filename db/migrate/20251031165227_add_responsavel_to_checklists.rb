class AddResponsavelToChecklists < ActiveRecord::Migration[7.1]
  def change
    add_column :checklists, :responsavel, :string
  end
end
