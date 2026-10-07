module EmployeeCareerRegistration
  extend ActiveSupport::Concern

  included do
    attr_accessor :career_starts_on, :career_cargo, :career_recorded_by
    validate :career_registration_fields, on: :create
    after_create :register_employee_career
    validate :career_fields_are_readonly, on: :update
    after_update :update_employee_identity
  end

  def operational_role_on(date)
    employee&.role_on(date)
  end

  private

  def career_registration_fields
    return if employee_id.present?
    errors.add(:career_starts_on, 'informe a data efetiva do cargo inicial') if career_starts_on.blank? && (is_a?(Driver) || is_a?(Ajudante) || career_recorded_by.present?)
    Date.iso8601(career_starts_on.to_s) if career_starts_on.present?
    errors.add(:base, 'Já existe colaborador com essa matrícula. Registre a movimentação no RH.') if Employee.exists?(matricula: matricula)
  rescue Date::Error
    errors.add(:career_starts_on, 'data inválida')
  end

  def register_employee_career
    Employees::Registry.register!(self)
  end

  def career_fields_are_readonly
    return unless employee
    if (has_attribute?(:promax) && will_save_change_to_promax?) || (has_attribute?(:turno) && will_save_change_to_turno?)
      errors.add(:base, 'Registre a mudança de código, cargo ou turno no histórico do colaborador, com data efetiva.')
    end
  end

  def update_employee_identity
    return if saved_change_to_employee_id?
    return unless employee && (saved_changes.keys & Employees::Registry::IDENTITY_FIELDS).any?
    Employees::Registry.remember_name!(employee, nome_before_last_save) if saved_change_to_nome?
    Employees::Registry.update!(employee, attributes: attributes.slice(*Employees::Registry::IDENTITY_FIELDS),
      user: career_recorded_by, reason: 'Atualização pelo cadastro operacional anterior')
  end
end
