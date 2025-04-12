class ChangeDataColumnTypeInMapas < ActiveRecord::Migration[7.1]
  def change
    change_column :mapas, :data, :string
  end
end
