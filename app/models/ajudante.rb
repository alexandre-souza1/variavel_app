class Ajudante < ApplicationRecord
  belongs_to :employee, optional: true
  include EmployeeCareerRegistration
  has_many :mapas, foreign_key: :matric_ajudante, primary_key: :promax
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  def retire!(user: nil)
    employee ? employee.retire!(user: user) : update!(active: false, retired_at: Date.current)
  end
end
