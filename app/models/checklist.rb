class Checklist < ApplicationRecord
  belongs_to :user
  belongs_to :checklist_template
  belongs_to :plate, optional: true  # <-- ESSA LINHA É ESSENCIAL
  has_many :checklist_responses, dependent: :destroy
  accepts_nested_attributes_for :checklist_responses

    validate :validate_plate_presence_if_required
    validate :validate_reponsavel_presence_if_required
    validate :validate_vehicle_model_presence_if_required
    validate :validate_kilometer_presence_if_required
    validate :validate_gas_state_presence_if_required
    validate :validate_origin_presence_if_required

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
end
