class AllowFixedAsHelpers < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :time_off_memberships, name: 'time_off_valid_standard_operation'
    add_check_constraint :time_off_memberships,
      "standard_operation IS NULL OR (group_code = 'FIXO' AND fixed_weekday = 6 AND standard_operation IN ('vespertina', 'as'))",
      name: 'time_off_valid_standard_operation'
  end

  def down
    if select_value("SELECT 1 FROM time_off_memberships WHERE standard_operation = 'as' AND ajudante_id IS NOT NULL LIMIT 1")
      raise ActiveRecord::IrreversibleMigration, 'Há ajudantes fixos no AS; preserve os vínculos e o histórico.'
    end
    remove_check_constraint :time_off_memberships, name: 'time_off_valid_standard_operation'
    add_check_constraint :time_off_memberships,
      "standard_operation IS NULL OR (group_code = 'FIXO' AND fixed_weekday = 6 AND (standard_operation = 'vespertina' OR (standard_operation = 'as' AND driver_id IS NOT NULL)))",
      name: 'time_off_valid_standard_operation'
  end
end
