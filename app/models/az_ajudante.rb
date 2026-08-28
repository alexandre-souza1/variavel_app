class AzAjudante < ApplicationRecord
  validates :matricula, :nome, :turno, presence: true
  validates :matricula, uniqueness: true
  validates :turno, inclusion: { in: 0..2, message: "deve ser A, B ou C" }
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  def retire!
    update!(active: false, retired_at: Date.current)
  end
end
