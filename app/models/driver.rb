class Driver < ApplicationRecord
  belongs_to :employee, optional: true
  include EmployeeCareerRegistration
  has_many :mapas, foreign_key: :matric_motorista, primary_key: :promax
  has_many :autonomies, as: :user
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  def retire!(user: nil)
    employee ? employee.retire!(user: user) : update!(active: false, retired_at: Date.current)
  end
end
