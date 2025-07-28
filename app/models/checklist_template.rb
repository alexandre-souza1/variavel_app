class ChecklistTemplate < ApplicationRecord
  has_many :checklist_items, dependent: :destroy
  validates :name, presence: true

  # default false se quiser
  attribute :plate_required, :boolean, default: false
end
