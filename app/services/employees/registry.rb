module Employees
  # The only writer of identity data and compatibility records. update_all is
  # intentional here: adapters must not recursively register another person.
  class Registry
    MODELS = [Driver, Ajudante, Operator, AzAjudante].freeze
    IDENTITY_FIELDS = %w[nome matricula cpf data_nascimento active retired_at].freeze

    def self.create!(attributes:, role:, user:)
      Employee.transaction do
        person = Employee.create!(attributes)
        person.change_role!(role, user: user)
        person
      end
    end

    def self.update!(person, attributes:, user:, reason:)
      raise EmployeeRole::HistoryError, 'Informe o motivo da alteração.' if reason.to_s.strip.blank?
      attributes = attributes.to_h.stringify_keys
      autonomy_changed = attributes.key?('operational_autonomy')
      autonomy = attributes.delete('operational_autonomy')
      person.with_lock do
        before = person.attributes.slice(*IDENTITY_FIELDS).merge('operational_autonomy' => person.operational_autonomy)
        person.update!(attributes)
        if autonomy_changed
          adapter = autonomy_record(person.matricula)
          raise EmployeeRole::HistoryError, 'Autonomia exige vínculo vigente de motorista DU ou operador AZ.' unless adapter
          adapter.update!(autonomy: ActiveModel::Type::Boolean.new.cast(autonomy))
        end
        person.employee_career_events.create!(user: user, details: {
          action: 'update_identity', before: before,
          after: person.attributes.slice(*IDENTITY_FIELDS).merge('operational_autonomy' => person.operational_autonomy), reason: reason
        }) if user
      end
      person
    end

    def self.retire!(person, date: Date.current, user: nil, reason: 'Inativação do cadastro')
      person.with_lock do
        person.update!(active: false, retired_at: date)
        person.employee_career_events.create!(user: user, details: { action: 'retire', date: date, reason: reason }) if user
      end
      person
    end

    def self.register!(record)
      return if record.employee_id
      sector = record.is_a?(Operator) || record.is_a?(AzAjudante) ? 'az' : 'du'
      cargo = case record
              when Operator then 'operador'
              when Ajudante, AzAjudante then 'ajudante'
              else record.career_cargo.presence || 'motorista'
              end
      person = Employee.create!(record.attributes.slice(*IDENTITY_FIELDS))
      record.update_column(:employee_id, person.id)
      attributes = { sector: sector, cargo: cargo, promax: record.try(:promax), turno: record.try(:turno),
        starts_on: record.career_starts_on, reason: 'Cadastro inicial / importação' }
      if attributes[:starts_on].present?
        person.change_role!(attributes, user: record.career_recorded_by)
      else
        # Legacy callers may not supply a date; never invent one. Public forms
        # and new CSV imports require the actual effective date.
        person.employee_roles.create!(attributes.merge(legacy: true))
      end
      remember_name!(person, record.nome)
    end

    def self.synchronize!(person)
      return unless person.persisted?
      identity = person.attributes.slice(*IDENTITY_FIELDS).merge('updated_at' => Time.current)
      MODELS.each { |model| model.where(employee_id: person.id).update_all(identity) }
      remember_name!(person, person.nome)
      roles = person.employee_roles.reload.to_a
      roles.each do |role|
        model = model_for(role)
        next if model.where(employee_id: person.id).exists?
        fields = identity.merge('employee_id' => person.id, 'created_at' => Time.current)
        fields['promax'] = role.promax if role.du?
        fields['turno'] = role.turno if role.az?
        model.insert_all!([fields])
      end
      current = roles.find { |role| role.covers?(Date.current) }
      if current
        specific = current.du? ? { promax: current.promax } : { turno: current.turno }
        model_for(current).where(employee_id: person.id).update_all(specific.merge(updated_at: Time.current))
      end
      person.association(:employee_roles).reset
    end

    def self.model_for(role)
      role.az? ? (role.cargo == 'operador' ? Operator : AzAjudante) : (role.cargo == 'ajudante' ? Ajudante : Driver)
    end

    def self.autonomy_record(registration, date: Date.current)
      people = Employee.active.with_career_history.where(matricula: registration).limit(2).to_a
      return if people.many?
      if people.one?
        role = people.first.role_on(date)
        return unless role && ((role.du? && %w[motorista van].include?(role.cargo)) || (role.az? && role.cargo == 'operador'))
        model = model_for(role)
        return model.where(employee_id: people.first.id).order(:id).first
      end
      # Only pre-migration records are eligible for this fallback.
      legacy = [Driver, Operator].flat_map { |model| model.active.where(employee_id: nil, matricula: registration).limit(2).to_a }
      legacy.first if legacy.one?
    end

    def self.operator_for_name(name, date:)
      owners = EmployeeName.owners(name)
      return if owners.many?
      if owners.one?
        person = Employee.find(owners.first)
        role = person.role_on(date)
        return unless role&.az? && role.cargo == 'operador'
        return person.operators.order(:id).first
      end
      key = EmployeeName.normalize(name)
      legacy = Operator.where(employee_id: nil).select { |record| EmployeeName.normalize(record.nome) == key }
      legacy.first if key.present? && legacy.one?
    end

    def self.remember_name!(person, name)
      return if name.blank?
      key = EmployeeName.normalize(name)
      EmployeeName.find_or_create_by!(employee: person, normalized_name: key) { |entry| entry.name = name }
    end
  end
end
