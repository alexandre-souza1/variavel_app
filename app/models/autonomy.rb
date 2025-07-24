class Autonomy < ApplicationRecord
  has_one_attached :evidence
  belongs_to :user, polymorphic: true
  validate :user_has_autonomy_permission

  private

  def user_has_autonomy_permission
    # Verifica se existe um Driver ou Operator com a matrícula e autonomy=true
    driver_valid = Driver.exists?(registration: registration, autonomy: true)
    operator_valid = Operator.exists?(registration: registration, autonomy: true)

    unless driver_valid || operator_valid
      errors.add(:registration, "não possui permissão para registrar autonomia ou não foi encontrada")
    end
  end
end
