class Checklist < ApplicationRecord
  belongs_to :user
  belongs_to :checklist_template
  belongs_to :plate, optional: true  # <-- ESSA LINHA É ESSENCIAL
  has_many :checklist_responses, dependent: :destroy
  accepts_nested_attributes_for :checklist_responses

    validate :validate_plate_presence_if_required

  def validate_plate_presence_if_required
    if checklist_template.plate_required? && plate.nil?
      errors.add(:plate, "é obrigatória para este checklist")
    end
  end
end
