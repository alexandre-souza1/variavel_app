class AzAjudante < ApplicationRecord
  belongs_to :employee, optional: true
  include EmployeeCareerRegistration
  validates :matricula, :nome, :turno, presence: true
  validates :matricula, uniqueness: true
  validates :turno, inclusion: { in: 0..2, message: "deve ser A, B ou C" }
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  def retire!(user: nil)
    employee ? employee.retire!(user: user) : update!(active: false, retired_at: Date.current)
  end
end
