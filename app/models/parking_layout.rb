class ParkingLayout < ApplicationRecord
  SLOTS = JSON.parse(Rails.root.join("config/parking_layout.json").read).map(&:freeze).freeze
  SLOT_KEYS = SLOTS.map { |slot| slot.fetch("number").to_s }.freeze
  PLATE_FORMAT = /\A[A-Z]{3}[0-9][A-Z0-9][0-9]{2}\z/

  belongs_to :updated_by, class_name: "User", optional: true
  validate :valid_distribution

  def self.current
    find_by(id: 1) || new(id: 1, assignments: initial_assignments)
  end

  def self.initial_assignments
    active = active_plates
    SLOTS.to_h do |slot|
      plate = slot.fetch("plate")
      [slot.fetch("number").to_s, active.include?(plate) ? plate : ""]
    end
  end

  def self.normalize_plate(value)
    value.to_s.upcase.gsub(/[^A-Z0-9]/, "")
  end

  def self.active_plates
    Plate.active.where(tipo: ["Caminhão", "Van"]).pluck(:placa)
      .map { |value| normalize_plate(value) }
      .select { |value| value.match?(PLATE_FORMAT) }.uniq.sort
  end

  def available_plates
    self.class.active_plates
  end

  # Retired or renamed plates never appear on the public map or in the editor.
  def visible_assignments
    active = available_plates
    assignments.transform_values { |plate| active.include?(plate) ? plate : "" }
  end

  private

  def valid_distribution
    unless assignments.is_a?(Hash) && assignments.keys.sort == SLOT_KEYS.sort
      errors.add(:base, "Informe a distribuição das 40 vagas do pátio.")
      return
    end

    values = assignments.values
    unless values.all? { |value| value.is_a?(String) && (value.empty? || value.match?(PLATE_FORMAT)) }
      errors.add(:base, "Uma ou mais placas têm formato inválido.")
      return
    end

    occupied = values.reject(&:empty?)
    errors.add(:base, "Uma placa não pode ocupar mais de uma vaga.") if occupied.uniq.size != occupied.size
    errors.add(:base, "Selecione apenas caminhões e vans ativos no cadastro de placas.") if (occupied - available_plates).any?
  end
end
