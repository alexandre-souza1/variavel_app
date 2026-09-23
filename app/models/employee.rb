class Employee < ApplicationRecord
  CARGO_NIVEL = { 'ajudante' => 0, 'van' => 1, 'motorista' => 2 }.freeze

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
    resolve_link_pair(source)
    true
  rescue EmployeeRole::HistoryError
    false
  end

  # Returns [destination, source] regardless of which duplicate cadastro the
  # user opened. The RH cadastro wins when one side already has a non-legacy
  # history; two purely legacy records are ordered by cargo progression.
  def resolve_link_pair(other, invert: false)
    raise EmployeeRole::HistoryError, 'Selecione outro cadastro.' if other == self

    cpf_digits = cpf.to_s.gsub(/\D/, '')
    other_cpf_digits = other.cpf.to_s.gsub(/\D/, '')
    raise EmployeeRole::HistoryError, 'Os cadastros devem ter o mesmo CPF para confirmar a identidade.' if cpf_digits.blank? || cpf_digits != other_cpf_digits

    people = [self, other]
    single_legacy = people.select { |person| person.employee_roles.size == 1 && person.employee_roles.first.legacy? }
    established = people.reject { |person| person.employee_roles.size == 1 && person.employee_roles.first.legacy? }

    if established.size == 1 && single_legacy.size == 1
      destination = established.first
      source = single_legacy.first
    elsif people.all? { |person| person.employee_roles.size == 1 && person.employee_roles.first.legacy? }
      ranked = people.sort_by { |person| CARGO_NIVEL.fetch(person.employee_roles.first.cargo, -1) }
      raise EmployeeRole::HistoryError, 'Os cadastros têm o mesmo cargo legado. Informe ao RH qual deles deve permanecer como cadastro principal.' if ranked.first.employee_roles.first.cargo == ranked.last.employee_roles.first.cargo
      destination, source = ranked
    else
      raise EmployeeRole::HistoryError, 'Não foi possível determinar com segurança o cadastro principal e o cadastro legado.'
    end

    destination, source = source, destination if invert

    unless source.employee_roles.size == 1
      raise EmployeeRole::HistoryError, 'O cadastro incorporado precisa ter apenas uma vigência para que o histórico seja mesclado com segurança.'
    end

    [destination, source]
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
    return unless role
    return role if role.matches_map?(mapa)

    # A correção manual existe para mapas legados cuja posição operacional
    # não corresponde ao cargo cadastrado. A pessoa ainda precisa ser dona do
    # código usado no mapa; o override só corrige a regra aplicada naquele mapa.
    role if mapa.cargo_override.present? && mapa.employee_codes.include?(role.promax.to_s)
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
      if previous && EmployeeRole::CARGOS.value?(role.cargo) && !EmployeeRole::PROGRESSAO.fetch(previous.cargo, []).include?(role.cargo)
        allowed = EmployeeRole::PROGRESSAO.fetch(previous.cargo, []).map { |cargo| EmployeeRole::CARGOS.key(cargo) }
        next_cargos = allowed.any? ? allowed.to_sentence : 'nenhum cargo posterior'
        raise EmployeeRole::HistoryError, "#{previous.label} não pode ser alterado para #{role.label}. Próximos cargos permitidos: #{next_cargos}."
      end
      previous_ends_on = previous&.ends_on
      previous&.update!(ends_on: role.starts_on - 1.day)
      role.save!
      employee_career_events.create!(user: user, details: { action: 'change_role', previous_role_id: previous&.id, previous_ends_on: previous_ends_on, role: role.attributes })
      role
    end
  end

  def merge_linked_role!(role_attributes, starts_on:, reason:, user:)
    effective_date = Date.iso8601(starts_on.to_s)
    incoming_cargo = role_attributes['cargo'] || role_attributes[:cargo]
    incoming_promax = role_attributes['promax'] || role_attributes[:promax]
    incoming_legacy = role_attributes['legacy'] || role_attributes[:legacy]
    latest = employee_roles.order(Arel.sql('starts_on DESC NULLS LAST')).first

    if latest.nil? || EmployeeRole::PROGRESSAO.fetch(latest.cargo, []).include?(incoming_cargo)
      return change_role!({ cargo: incoming_cargo, promax: incoming_promax, starts_on: effective_date,
        reason: reason }, user: user)
    end

    first = employee_roles.order(Arel.sql('starts_on ASC NULLS FIRST')).first
    unless employee_roles.size == 1 && first && EmployeeRole::PROGRESSAO.fetch(incoming_cargo, []).include?(first.cargo)
      raise EmployeeRole::HistoryError, "A posição escolhida não forma uma progressão válida entre #{first&.label || 'os cargos'} e #{EmployeeRole::CARGOS.key(incoming_cargo) || incoming_cargo}."
    end
    raise EmployeeRole::HistoryError, 'A data da progressão deve ser anterior ou igual ao início do cargo principal.' if first.starts_on && effective_date > first.starts_on

    previous_starts_on = role_attributes['starts_on'] || role_attributes[:starts_on]
    previous_starts_on = Date.iso8601(previous_starts_on.to_s) if previous_starts_on.present? && !previous_starts_on.is_a?(Date)
    previous_starts_on ||= effective_date - 1.day if first.starts_on
    raise EmployeeRole::HistoryError, 'A vigência do cargo incorporado deve começar antes da progressão.' if previous_starts_on && previous_starts_on >= effective_date

    with_lock do
      self.class.connection.execute("SELECT pg_advisory_xact_lock(739231200)")
      original_first = first.attributes
      first.update!(starts_on: effective_date)
      inserted = employee_roles.create!(cargo: incoming_cargo, promax: incoming_promax,
        starts_on: previous_starts_on, ends_on: effective_date - 1.day,
        legacy: incoming_legacy, reason: reason, created_by: user)
      employee_career_events.create!(user: user, details: {
        action: 'merge_previous_role', role: inserted.attributes,
        adjusted_role: original_first, reason: reason
      })
      inserted
    end
  end

  def merge_variable_closings_from!(source)
    used_revisions = variable_closings.group_by { |closing| [closing.year, closing.month] }
      .transform_values { |closings| closings.map(&:revision).to_set }
    merged = []

    source.variable_closings.order(:year, :month, :revision, :id).to_a.each do |closing|
      period = [closing.year, closing.month]
      revisions = used_revisions[period] ||= Set.new
      revision = closing.revision
      if revisions.include?(revision)
        revision = revisions.max + 1
      end
      VariableClosing.where(id: closing.id).update_all(employee_id: id, revision: revision, updated_at: Time.current)
      revisions.add(revision)
      merged << { closing_id: closing.id, year: closing.year, month: closing.month,
                  original_revision: closing.revision, revision: revision }
    end
    merged
  end
end
