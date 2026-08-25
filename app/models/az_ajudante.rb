class AzAjudante < ApplicationRecord
  validates :matricula, :nome, :turno, presence: true
  validates :matricula, uniqueness: true
  validates :turno, inclusion: { in: 0..2, message: "deve ser A, B ou C" }
end
