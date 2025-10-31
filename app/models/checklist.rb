class Checklist < ApplicationRecord
  belongs_to :user
  belongs_to :checklist_template
  belongs_to :plate, optional: true  # <-- ESSA LINHA É ESSENCIAL
  has_many :checklist_responses, dependent: :destroy
  accepts_nested_attributes_for :checklist_responses

    validate :validate_plate_presence_if_required

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
end
