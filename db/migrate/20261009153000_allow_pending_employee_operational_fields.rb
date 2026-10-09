class AllowPendingEmployeeOperationalFields < ActiveRecord::Migration[7.1]
  def change
    remove_check_constraint :employee_roles,
      "(sector = 'du' AND cargo IN ('motorista', 'van', 'ajudante') AND promax IS NOT NULL) OR (sector = 'az' AND cargo IN ('operador', 'ajudante') AND ((turno IS NOT NULL AND turno BETWEEN 0 AND 2) OR (legacy = TRUE AND turno IS NULL)))",
      name: 'employee_role_valid_profile'
    add_check_constraint :employee_roles,
      "(sector = 'du' AND cargo IN ('motorista', 'van', 'ajudante') AND (promax IS NOT NULL OR pending_start = TRUE)) OR (sector = 'az' AND cargo IN ('operador', 'ajudante') AND ((turno IS NOT NULL AND turno BETWEEN 0 AND 2) OR ((legacy = TRUE OR pending_start = TRUE) AND turno IS NULL)))",
      name: 'employee_role_valid_profile'
  end
end
