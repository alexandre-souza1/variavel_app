class ChecklistTemplate < ApplicationRecord
  has_many :checklist_items, dependent: :destroy
  validates :name, presence: true

  # default false se quiser
  attribute :plate_required, :boolean, default: false
  attribute :kilometer_required, :boolean, default: false
  attribute :gas_state_required, :boolean, default: false
  attribute :vehicle_model_required, :boolean, default: false
  attribute :responsavel_required, :boolean, default: false
end
