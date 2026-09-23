class CreateEmployeeCareerHistory < ActiveRecord::Migration[7.1]
  def up
    create_table :employees do |t|
      t.string :nome, null: false
      t.string :matricula, null: false
      t.string :cpf
      t.date :data_nascimento
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_index :employees, :matricula
    create_table :employee_roles do |t|
      t.references :employee, null: false, foreign_key: true
      t.string :cargo, null: false
      t.string :promax, null: false
      t.date :starts_on
      t.date :ends_on
      t.boolean :legacy, default: false, null: false
      t.text :reason, null: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :employee_roles, [:promax, :cargo]
    add_check_constraint :employee_roles, "starts_on IS NULL OR ends_on IS NULL OR ends_on >= starts_on", name: "employee_role_valid_dates"
    add_check_constraint :employee_roles, "starts_on IS NOT NULL OR legacy = TRUE", name: "employee_role_start_required"
    add_check_constraint :employee_roles, "cargo IN ('motorista', 'van', 'ajudante')", name: "employee_role_valid_cargo"
    [:drivers, :ajudantes].each { |table| add_reference table, :employee, foreign_key: true }
    create_table :employee_career_events do |t|
      t.references :employee, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    create_table :variable_closings do |t|
      t.references :employee, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :year, null: false
      t.integer :month, null: false
      t.integer :revision, null: false
      t.text :reason, null: false
      t.jsonb :result, null: false
      t.timestamps
    end
    add_index :variable_closings, [:employee_id, :year, :month, :revision], unique: true, name: 'index_variable_closings_revision'
    create_table :calculation_rate_versions do |t|
      t.string :categoria, null: false
      t.string :nome, null: false
      t.decimal :valor, precision: 16, scale: 6, null: false
      t.date :effective_on
      t.timestamps
    end
    add_index :calculation_rate_versions, [:categoria, :nome, :effective_on], name: 'index_calculation_rate_versions_lookup'

    # The former hardcoded rule is converted to DATA only, never used at runtime.
    # Unknown hire dates remain unknown. No promotion date is inferred.
    suppress_messages do
    [:drivers, :ajudantes].each do |table|
      select_all("SELECT * FROM #{table} ORDER BY id").each do |person|
        next if person['matricula'].blank? || person['promax'].blank? || person['nome'].blank?
        employee_id = select_value(<<~SQL)
          INSERT INTO employees (nome, matricula, cpf, data_nascimento, active, created_at, updated_at)
          VALUES (#{quote(person['nome'])}, #{quote(person['matricula'])}, #{quote(person['cpf'])}, #{quote(person['data_nascimento'])}, #{quote(person['active'])}, NOW(), NOW()) RETURNING id
        SQL
        cargo = table == :ajudantes ? 'ajudante' : (person['promax'] == '86' ? 'van' : 'motorista')
        execute <<~SQL
          INSERT INTO employee_roles (employee_id, cargo, promax, legacy, reason, created_at, updated_at)
          VALUES (#{employee_id}, #{quote(cargo)}, #{quote(person['promax'])}, TRUE, 'Cadastro legado: início desconhecido; revisar histórico no RH.', NOW(), NOW())
        SQL
        execute "UPDATE #{table} SET employee_id = #{employee_id} WHERE id = #{person['id'].to_i}"
      end
    end
    end
    execute <<~SQL
      INSERT INTO calculation_rate_versions (categoria, nome, valor, created_at, updated_at)
      SELECT DISTINCT ON (categoria, nome) categoria, nome, valor, NOW(), NOW()
      FROM parametro_calculos WHERE categoria IS NOT NULL AND nome IS NOT NULL AND valor IS NOT NULL
      ORDER BY categoria, nome, id
    SQL
  end

  def down
    drop_table :calculation_rate_versions
    drop_table :variable_closings
    drop_table :employee_career_events
    [:drivers, :ajudantes].each { |table| remove_reference table, :employee, foreign_key: true }
    drop_table :employee_roles
    drop_table :employees
  end
end
