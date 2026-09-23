module EmployeeCareerRegistration
  extend ActiveSupport::Concern

  included do
    attr_accessor :career_starts_on, :career_cargo, :career_recorded_by
    validate :career_registration_fields, on: :create
    after_create :register_employee_career
  end

  private

  def career_registration_fields
    return if employee_id.present?
    errors.add(:career_starts_on, 'informe a data efetiva do cargo inicial') if career_starts_on.blank?
    Date.iso8601(career_starts_on.to_s) if career_starts_on.present?
    errors.add(:base, 'Já existe colaborador com essa matrícula. Registre a movimentação no RH.') if Employee.exists?(matricula: matricula)
  rescue Date::Error
    errors.add(:career_starts_on, 'data inválida')
  end

  def register_employee_career
    return if employee_id.present?
    person = Employee.create!(nome: nome, matricula: matricula, cpf: cpf, data_nascimento: data_nascimento, active: active)
    cargo = is_a?(Ajudante) ? 'ajudante' : (career_cargo.presence || 'motorista')
    person.change_role!({ cargo: cargo, promax: promax, starts_on: career_starts_on, reason: 'Cadastro inicial / importação' }, user: career_recorded_by)
    update_column(:employee_id, person.id)
  end
end
