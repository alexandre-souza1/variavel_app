class Ajudante < ApplicationRecord
  has_many :mapas, foreign_key: :matric_ajudante, primary_key: :promax
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  def retire!
    update!(active: false, retired_at: Date.current)
  end
end
