class Autonomy < ApplicationRecord
  has_one_attached :evidence
  belongs_to :user, polymorphic: true
  validate :user_has_autonomy_permission

  private

  def user_has_autonomy_permission
    person = Employees::Registry.autonomy_record(registration)
    unless person&.autonomy && person == user
      errors.add(:registration, "não possui permissão para registrar autonomia ou não foi encontrada")
    end
  end
end
