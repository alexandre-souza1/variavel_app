class Checklist < ApplicationRecord
  belongs_to :user
  belongs_to :checklist_template
  belongs_to :plate, optional: true
  has_many :checklist_responses, dependent: :destroy
  accepts_nested_attributes_for :checklist_responses

  has_one_attached :photo_front
  has_one_attached :photo_left_truck
  has_one_attached :photo_left_trailer
  has_one_attached :photo_back
  has_one_attached :photo_right_trailer
  has_one_attached :photo_right_truck

  validate :validate_plate_presence_if_required
  validate :validate_reponsavel_presence_if_required
  validate :validate_vehicle_model_presence_if_required
  validate :validate_kilometer_presence_if_required
  validate :validate_gas_state_presence_if_required
  validate :validate_origin_presence_if_required
  validate :validate_photos_presence_if_required

  private

  def validate_plate_presence_if_required
    return unless checklist_template&.plate_required?

    if checklist_template.setor == "TRANSFERÊNCIA"
      if placa_manual.blank?
        errors.add(:placa_manual, "deve ser preenchida para checklists de Transferência")
      end
    else
      if plate_id.blank?
        errors.add(:plate, "deve ser selecionada")
      end
    end
  end

  def validate_reponsavel_presence_if_required
    return unless checklist_template&.responsavel_required?

    if responsavel.blank?
      errors.add(:responsavel, "deve ser preenchida")
    end
  end

  def validate_vehicle_model_presence_if_required
    return unless checklist_template&.vehicle_model_required?

    if vehicle_model.blank?
      errors.add(:vehicle_model, "deve ser preenchida")
    end
  end

  def validate_kilometer_presence_if_required
    return unless checklist_template&.kilometer_required?

    if kilometer.blank?
      errors.add(:kilometer, "deve ser preenchida")
    end
  end

  def validate_gas_state_presence_if_required
    return unless checklist_template&.gas_state_required?

    if gas_state.blank?
      errors.add(:gas_state, "deve ser preenchida")
    end
  end

  def validate_origin_presence_if_required
    return unless checklist_template&.origin_required?

    if origin.blank?
      errors.add(:origin, "deve ser preenchida")
    end
  end

  def validate_photos_presence_if_required
    return unless checklist_template&.photos_required?

    required_photos = {
      photo_front: "Frente",
      photo_back: "Traseira",
      photo_left_truck: "Lado esquerdo (cavalo)",
      photo_left_trailer: "Lado esquerdo (implemento)",
      photo_right_trailer: "Lado direito (implemento)",
      photo_right_truck: "Lado direito (cavalo)"
    }

    required_photos.each do |photo_attr, label|
      unless send(photo_attr).attached?
        errors.add(photo_attr, "deve ser anexada (#{label})")
      end
    end
  end
end
