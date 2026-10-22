class AddHistoricalEmployees < ActiveRecord::Migration[7.1]
  def up
    add_column :employees, :historical_only, :boolean, default: false, null: false
    change_column_null :employees, :matricula, true
    add_check_constraint :employees, "(historical_only AND NOT active) OR (NOT historical_only AND matricula IS NOT NULL)", name: "employees_historical_identity"
    remove_check_constraint :employee_roles, name: "employee_role_valid_profile"
    add_check_constraint :employee_roles, profile_constraint(allow_legacy: true), name: "employee_role_valid_profile"
  end

  def down
    if select_value("SELECT 1 FROM employees WHERE historical_only LIMIT 1")
      raise ActiveRecord::IrreversibleMigration, "Há cadastros históricos; preserve seus vínculos antes de remover este recurso."
    end
    remove_check_constraint :employee_roles, name: "employee_role_valid_profile"
    add_check_constraint :employee_roles, profile_constraint(allow_legacy: false), name: "employee_role_valid_profile"
    remove_check_constraint :employees, name: "employees_historical_identity"
    change_column_null :employees, :matricula, false
    remove_column :employees, :historical_only
  end

  private

  def profile_constraint(allow_legacy:)
    <<~SQL.squish
      (sector = 'du' AND cargo IN ('motorista', 'van', 'ajudante') AND
        (promax IS NOT NULL OR pending_start = TRUE #{'OR legacy = TRUE' if allow_legacy})) OR
      (sector = 'az' AND cargo IN ('operador', 'ajudante') AND
        ((turno IS NOT NULL AND turno BETWEEN 0 AND 2) OR ((legacy = TRUE OR pending_start = TRUE) AND turno IS NULL)))
    SQL
  end
end
