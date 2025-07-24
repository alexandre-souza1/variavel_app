class AddAutonomyToOperators < ActiveRecord::Migration[7.1]
  def change
    add_column :operators, :autonomy, :boolean, default: false, null: false
  end
end
