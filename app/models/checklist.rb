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

  # Validação para foto frontal
  if checklist_template.photo_front_required? && !photo_front.attached?
    errors.add(:photos_required, "deve ser anexada")
  end

  # Validação para foto traseira
  if checklist_template.photo_back_required? && !photo_back.attached?
    errors.add(:photos_required, "deve ser anexada")
  end

  # Validação para foto lateral esquerda do caminhão
  if checklist_template.photo_left_truck_required? && !photo_left_truck.attached?
    errors.add(:photos_required, "deve ser anexada")
  end

  # Validação para foto lateral esquerda do reboque
  if checklist_template.photo_left_trailer_required? && !photo_left_trailer.attached?
    errors.add(:photos_required, "deve ser anexada")
  end

  # Validação para foto lateral direita do reboque
  if checklist_template.photo_right_trailer_required? && !photo_right_trailer.attached?
    errors.add(:photos_required, "deve ser anexada")
  end

  # Validação para foto lateral direita do caminhão
  if checklist_template.photo_right_truck_required? && !photo_right_truck.attached?
    errors.add(:photos_required, "deve ser anexada")
  end
end
end
