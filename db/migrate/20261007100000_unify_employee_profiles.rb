class UnifyEmployeeProfiles < ActiveRecord::Migration[7.1]
  def up
    add_column :employees, :retired_at, :date
    add_column :employee_roles, :sector, :string, default: 'du', null: false
    add_column :employee_roles, :turno, :integer
    change_column_null :employee_roles, :promax, true
    remove_check_constraint :employee_roles, name: 'employee_role_valid_cargo'
    add_check_constraint :employee_roles,
      "(sector = 'du' AND cargo IN ('motorista', 'van', 'ajudante') AND promax IS NOT NULL) OR (sector = 'az' AND cargo IN ('operador', 'ajudante') AND ((turno IS NOT NULL AND turno BETWEEN 0 AND 2) OR (legacy = TRUE AND turno IS NULL)))",
      name: 'employee_role_valid_profile'
    add_index :employee_roles, [:sector, :cargo, :starts_on, :ends_on], name: 'index_employee_roles_profile_period'
    %i[operators az_ajudantes].each do |table|
      change_column table, :matricula, :string, using: 'matricula::text'
      add_reference table, :employee, foreign_key: true
    end
    add_reference :time_off_memberships, :employee, foreign_key: true
    add_column :variable_closings, :sector, :string, default: 'du', null: false
    remove_index :variable_closings, name: 'index_variable_closings_revision'
    add_index :variable_closings, [:employee_id, :sector, :year, :month, :revision], unique: true, name: 'index_variable_closings_revision'
    add_check_constraint :variable_closings, "sector IN ('du', 'az')", name: 'variable_closing_valid_sector'
    create_table :employee_names do |t|
      t.references :employee, null: false, foreign_key: true
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.timestamps
    end
    add_index :employee_names, [:employee_id, :normalized_name], unique: true
    add_index :employee_names, :normalized_name
    %i[az_rv_points az_rv_tasks az_rv_on_demand_activities wms_tasks].each do |table|
      add_reference table, :employee, foreign_key: true
    end
    backfill_az(:operators, 'operador')
    backfill_az(:az_ajudantes, 'ajudante')
    select_all('SELECT id, nome FROM employees').each { |person| remember_name(person['id'], person['nome']) }
    %i[drivers ajudantes operators az_ajudantes].each do |table|
      select_all("SELECT employee_id, nome FROM #{table} WHERE employee_id IS NOT NULL").each do |person|
        remember_name(person['employee_id'], person['nome'])
      end
    end
    execute <<~SQL
      UPDATE time_off_memberships m SET employee_id = d.employee_id FROM drivers d WHERE m.driver_id = d.id;
      UPDATE time_off_memberships m SET employee_id = a.employee_id FROM ajudantes a WHERE m.ajudante_id = a.id;
      UPDATE wms_tasks t SET employee_id = o.employee_id FROM operators o WHERE t.operator_id = o.id;
    SQL
    %i[az_rv_points az_rv_tasks az_rv_on_demand_activities].each do |table|
      execute <<~SQL
        UPDATE #{table} r SET employee_id = n.employee_id
        FROM (SELECT normalized_name, MIN(employee_id) employee_id FROM employee_names
              GROUP BY normalized_name HAVING COUNT(DISTINCT employee_id) = 1) n
        WHERE r.employee_key = n.normalized_name;
      SQL
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Os vínculos DU/AZ e os históricos precisam ser preservados. Reverta a aplicação mantendo este schema compatível.'
  end

  private

  def backfill_az(table, cargo)
    select_all("SELECT * FROM #{table} ORDER BY id").each do |person|
      # Transfers need a real date. Reuse only an identical legacy AZ profile;
      # never infer a transfer from a matching DU registration or name.
      digits = person['cpf'].to_s.gsub(/\D/, '')
      candidate = if digits.present? && digits.length <= 11
        select_value(<<~SQL)
          SELECT e.id FROM employees e JOIN employee_roles r ON r.employee_id = e.id
          WHERE e.matricula = #{connection.quote(person['matricula'].to_s)}
            AND regexp_replace(e.cpf, '[^0-9]', '', 'g') = #{connection.quote(digits)}
            AND e.data_nascimento IS NOT DISTINCT FROM #{connection.quote(person['data_nascimento'])}
            AND r.sector = 'az' AND r.cargo = #{connection.quote(cargo)} AND r.legacy = TRUE
            AND r.turno IS NOT DISTINCT FROM #{connection.quote(person['turno'])}
          GROUP BY e.id ORDER BY e.id LIMIT 1
        SQL
      end
      employee_id = candidate || select_value(<<~SQL)
        INSERT INTO employees (nome, matricula, cpf, data_nascimento, active, retired_at, created_at, updated_at)
        VALUES (#{connection.quote(person['nome'].presence || 'Cadastro AZ sem nome')}, #{connection.quote(person['matricula'].to_s)},
                #{connection.quote(person['cpf'])}, #{connection.quote(person['data_nascimento'])}, #{connection.quote(person['active'])},
                #{connection.quote(person['retired_at'])}, NOW(), NOW()) RETURNING id
      SQL
      unless candidate
        turno = person['turno'].present? && (0..2).cover?(person['turno'].to_i) ? person['turno'] : nil
        execute <<~SQL
          INSERT INTO employee_roles (employee_id, sector, cargo, turno, legacy, reason, created_at, updated_at)
          VALUES (#{employee_id}, 'az', #{connection.quote(cargo)}, #{connection.quote(turno)}, TRUE,
                  'Cadastro AZ legado: início desconhecido; revisar histórico no RH.', NOW(), NOW())
        SQL
      end
      execute "UPDATE #{table} SET employee_id = #{employee_id} WHERE id = #{person['id'].to_i}"
    end
  end

  def remember_name(employee_id, name)
    return if name.blank?
    key = name.to_s.unicode_normalize(:nfkd).encode('ASCII', invalid: :replace, undef: :replace, replace: '')
      .downcase.gsub(/[^a-z0-9]+/, ' ').strip
    execute <<~SQL
      INSERT INTO employee_names (employee_id, name, normalized_name, created_at, updated_at)
      VALUES (#{employee_id.to_i}, #{connection.quote(name)}, #{connection.quote(key)}, NOW(), NOW()) ON CONFLICT DO NOTHING
    SQL
  end
end
