class PeopleCycleFeedback < ApplicationRecord
  belongs_to :imported_by, class_name: "User"
  validates :cycle, :employee_name, :employee_key, :stage, :response, presence: true

  def self.normalize(value)
    I18n.transliterate(value.to_s).downcase.squish
  end

  def self.for_identity(identity)
    employee = identity.record.is_a?(Employee) ? identity.record : (identity.record.respond_to?(:employee) ? identity.record.employee : nil)
    if employee
      return where(profile: 'colaborador', employee_id: employee.id)
        .or(where(profile: 'motorista', employee_id: employee.drivers.select(:id)))
        .or(where(profile: 'ajudante', employee_id: employee.ajudantes.select(:id)))
        .where(employee_key: normalize(employee.nome)).order(cycle: :desc, stage: :asc)
    end
    where(profile: identity.profile, employee_id: identity.record.id,
          employee_key: normalize(identity.name)).order(cycle: :desc, stage: :asc)
  end
end
