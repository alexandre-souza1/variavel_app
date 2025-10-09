class RemunerationCategoryValue < ApplicationRecord
  belongs_to :vehicle_remuneration
  belongs_to :budget_category

  validates :value, numericality: true
  validates :budget_category_id, uniqueness: { scope: :vehicle_remuneration_id }
end
