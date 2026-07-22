class AddSectorToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :sector, :integer
  end
end
