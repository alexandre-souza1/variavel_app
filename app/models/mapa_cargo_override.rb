class MapaCargoOverride < ApplicationRecord
  belongs_to :mapa
  belongs_to :user

  validates :previous_cargo, inclusion: { in: Mapa::CARGOS }, allow_blank: true
  validates :cargo, inclusion: { in: Mapa::CARGOS }, allow_blank: true
  validates :reason, presence: true

  validate :cargo_must_change

  private

  def cargo_must_change
    errors.add(:cargo, 'deve ser diferente do cargo anterior') if previous_cargo.to_s.presence == cargo.to_s.presence
  end
end
