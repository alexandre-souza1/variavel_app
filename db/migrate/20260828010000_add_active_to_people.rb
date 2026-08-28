class AddActiveToPeople < ActiveRecord::Migration[7.1]
  TABLES = %i[drivers operators users ajudantes az_ajudantes].freeze

  def change
    TABLES.each do |table|
      add_column table, :active, :boolean, null: false, default: true
      add_column table, :retired_at, :date
      add_index table, :active
    end
  end
end
