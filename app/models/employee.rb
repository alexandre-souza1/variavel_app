class Employee < ApplicationRecord
  has_many :employee_roles, dependent: :restrict_with_exception
  has_many :employee_career_events, dependent: :restrict_with_exception
  has_many :variable_closings, dependent: :restrict_with_exception
  has_many :drivers, dependent: :restrict_with_exception
  has_many :ajudantes, dependent: :restrict_with_exception
  validates :nome, :matricula, presence: true
  validates :matricula, uniqueness: true, on: :create

  scope :with_career_history, -> { where(id: EmployeeRole.select(:employee_id)) }

  def self.duplicate_registration_counts(registrations)
    with_career_history.where(matricula: registrations).where.not(matricula: [nil, ''])
      .group(:matricula).having('COUNT(*) > 1').count
  end

  def linkable_legacy_source?(source)
    cpf_digits = cpf.to_s.gsub(/\D/, '')
    cpf_digits.present? && cpf_digits == source.cpf.to_s.gsub(/\D/, '') &&
      source.employee_roles.size == 1 && source.employee_roles.first.legacy?
  end

  def role_on(date)
    return unless date
    matches = employee_roles.select { |role| role.covers?(date) }
    raise EmployeeRole::HistoryError, "Vigências sobrepostas para #{nome}." if matches.size > 1
    matches.first
  end

  def maps
    driver_codes = employee_roles.reject { |role| role.cargo == 'ajudante' }.map(&:promax).uniq
    helper_codes = employee_roles.select { |role| role.cargo == 'ajudante' }.map(&:promax).uniq
    Mapa.where(matric_motorista: driver_codes).or(Mapa.where(matric_ajudante: helper_codes)).or(Mapa.where(matric_ajudante_2: helper_codes))
  end

  def role_for(mapa)
    role = role_on(mapa.data_formatada)
    role if role&.matches_map?(mapa)
  end

  def revise_role!(role_id, attributes, user:)
    with_lock do
      self.class.connection.execute("SELECT pg_advisory_xact_lock(739231200)")
      roles = employee_roles.order(Arel.sql('starts_on ASC NULLS FIRST')).to_a
      role = roles.find { |item| item.id == role_id.to_i } || raise(ActiveRecord::RecordNotFound)
      index = roles.index(role)
      previous = index.positive? ? roles[index - 1] : nil
      following = roles[index + 1]
      before = roles.map(&:attributes)
      role.assign_attributes(attributes)
      raise EmployeeRole::HistoryError, 'Informe a data efetiva corrigida.' unless role.starts_on
      if (previous&.starts_on && role.starts_on <= previous.starts_on) || (following && role.starts_on >= following.starts_on)
        raise EmployeeRole::HistoryError, 'A correção deve manter a ordem das movimentações.'
      end
      # Temporarily save the predecessor boundary without overlap validation;
      # all intervals are validated before this transaction commits.
      previous&.update_columns(ends_on: role.starts_on - 1.day, updated_at: Time.current)
      role.save!
      previous&.validate!
      employee_career_events.create!(user: user, details: { action: 'revise_role', before: before, after: employee_roles.reload.map(&:attributes), reason: role.reason })
    end
  end

  def delete_last_role!(role_id, user:)
    with_lock do
      self.class.connection.execute("SELECT pg_advisory_xact_lock(739231200)")
      role = employee_roles.find(role_id)
      unless user.admin? && role.created_by_id == user.id
        raise EmployeeRole::HistoryError, 'Somente o administrador que registrou a movimentação pode excluí-la.'
      end
      latest = employee_roles.order(Arel.sql('starts_on DESC NULLS LAST')).first
      raise EmployeeRole::HistoryError, 'Exclua primeiro a movimentação mais recente.' unless role == latest
      event = employee_career_events.where("details ->> 'action' = ? AND details -> 'role' ->> 'id' = ?", 'change_role', role.id.to_s).order(:id).last
      previous = event && employee_roles.find_by(id: event.details['previous_role_id'])
      raise EmployeeRole::HistoryError, 'O cargo inicial não pode ser excluído por esta ação.' unless previous
      if employee_career_events.where("details ->> 'action' = ? AND details -> 'original_role' ->> 'cargo' = ?", 'link_record', role.cargo).any? { |link| link.created_at >= role.created_at }
        raise EmployeeRole::HistoryError, 'Esta movimentação envolve vínculo de cadastros. Revise o vínculo antes de excluir.'
      end
      removed = role.attributes
      role.destroy!
      previous.update!(ends_on: event.details['previous_ends_on'])
      employee_career_events.create!(user: user, details: { action: 'delete_role', removed_role: removed, restored_role: previous.attributes })
    end
  end

  def change_role!(attributes, user:)
    with_lock do
      self.class.connection.execute("SELECT pg_advisory_xact_lock(739231200)")
      role = employee_roles.new(attributes.merge(created_by: user))
      raise EmployeeRole::HistoryError, 'Informe a data efetiva da movimentação.' unless role.starts_on
      previous = employee_roles.where.not(id: role.id).order(Arel.sql('starts_on DESC NULLS LAST')).first
      if previous && previous.starts_on && role.starts_on <= previous.starts_on
        raise EmployeeRole::HistoryError, 'A movimentação deve ser posterior à última vigência. Corrija o histórico com uma revisão.'
      end
      previous_ends_on = previous&.ends_on
      previous&.update!(ends_on: role.starts_on - 1.day)
      role.save!
      employee_career_events.create!(user: user, details: { action: 'change_role', previous_role_id: previous&.id, previous_ends_on: previous_ends_on, role: role.attributes })
      role
    end
  end
end
