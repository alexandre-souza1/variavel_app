class PreserveEmployeeRegistrationAliases < ActiveRecord::Migration[7.1]
  def change
    add_column :employees, :registration_aliases, :jsonb, default: [], null: false
    add_index :employees, :registration_aliases, using: :gin
    reversible do |direction|
      direction.up { execute 'UPDATE employees SET registration_aliases = jsonb_build_array(matricula)' }
    end
  end
end
