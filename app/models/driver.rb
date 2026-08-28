class Driver < ApplicationRecord
  has_many :mapas, foreign_key: :matric_motorista, primary_key: :promax
  has_many :autonomies, as: :user
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  def retire!
    update!(active: false, retired_at: Date.current)
  end
end
