class BackfillEmployeeOperationalLinks < ActiveRecord::Migration[7.1]
  def up
    backfill(:drivers, 'du', %w[motorista van])
    backfill(:ajudantes, 'du', %w[ajudante])
    backfill(:operators, 'az', %w[operador])
    backfill(:az_ajudantes, 'az', %w[ajudante])
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Os cadastros operacionais provisionados podem ter referências históricas.'
  end

  private

  def backfill(table, sector, cargos)
    field = sector == 'du' ? 'promax' : 'turno'
    execute <<~SQL
      INSERT INTO #{table} (employee_id, nome, matricula, cpf, data_nascimento, active, retired_at, #{field}, created_at, updated_at)
      SELECT e.id, e.nome, e.matricula, e.cpf, e.data_nascimento, e.active, e.retired_at, r.#{field}, NOW(), NOW()
      FROM employees e
      JOIN (
        SELECT DISTINCT ON (employee_id) employee_id, #{field}
        FROM employee_roles WHERE sector = #{connection.quote(sector)} AND cargo IN (#{cargos.map { |cargo| connection.quote(cargo) }.join(', ')})
        ORDER BY employee_id,
          ((starts_on IS NULL OR starts_on <= CURRENT_DATE) AND (ends_on IS NULL OR ends_on >= CURRENT_DATE)) DESC,
          starts_on DESC NULLS LAST, id DESC
      ) r ON r.employee_id = e.id
      WHERE NOT EXISTS (SELECT 1 FROM #{table} adapter WHERE adapter.employee_id = e.id)
    SQL
  end
end
