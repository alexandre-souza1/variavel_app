class InvoiceGoalCategory < ApplicationRecord
  belongs_to :invoice_goal
  belongs_to :budget_category

  validates :budget_category_id, uniqueness: { scope: :invoice_goal_id }
end
