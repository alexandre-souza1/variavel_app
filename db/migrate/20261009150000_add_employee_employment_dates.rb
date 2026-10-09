class AddEmployeeEmploymentDates < ActiveRecord::Migration[7.1]
  def change
    add_column :employees, :registered_on, :date
    add_column :employee_roles, :pending_start, :boolean, default: false, null: false

    remove_check_constraint :employee_roles, 'starts_on IS NOT NULL OR legacy = TRUE', name: 'employee_role_start_required'
    add_check_constraint :employee_roles, 'starts_on IS NOT NULL OR legacy = TRUE OR pending_start = TRUE', name: 'employee_role_start_required'
    add_check_constraint :employee_roles, 'pending_start = FALSE OR (starts_on IS NULL AND ends_on IS NULL AND legacy = FALSE)', name: 'employee_role_pending_start_dates'
  end
end
